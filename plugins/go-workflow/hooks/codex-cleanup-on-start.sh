#!/bin/bash
# codex-cleanup-on-start.sh — SessionStart hook that self-heals stale
# gopher-ai installs in ~/.codex/.
#
# Two cleanups in one hook:
#
# 1. ~/.codex/skills/<name>/ — legacy flat-skill installs from the original
#    `--user` mode (which this repo no longer offers). Removed when:
#    - Directory name matches a gopher-ai skill name
#    - SKILL.md frontmatter `name:` matches the directory name
#    - SKILL.md sha256 matches a (hash, skill_name) pair in the shipped
#      legacy-skill-hashes.txt manifest
#
# 2. ~/.codex/plugins/<name>/ — UNMARKED legacy plugin installs from when the
#    README said "manually copy dist/codex/plugins/ to ~/.codex/plugins/".
#    Plugins installed by the current `--user` mode write a
#    .gopher-ai-installed/ marker; the hook leaves those alone. An unmarked
#    directory matching one of our seven plugin names AND containing a
#    .codex-plugin/plugin.json that looks like ours is candidate for removal.
#    These show up alongside the new install path and double-load skill
#    metadata (the entire reason this hook exists).
#
# Both cleanups are gated by a per-version marker so subsequent sessions are
# nearly free. Exits 0 on every path so it never blocks a session start.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$PLUGIN_ROOT/hooks/legacy-skill-hashes.txt"
SKILLS_HOME="$HOME/.codex/skills"
PLUGINS_HOME="$HOME/.codex/plugins"

# The seven plugins this repo ships for Codex. Used to scope the unmarked-
# plugin cleanup so we never touch unrelated user-installed plugins.
KNOWN_PLUGINS="go-dev go-web go-workflow gopher-guides llm-tools tailwind"

# Fast-exit: nothing to clean.
[[ -d "$HOME/.codex" ]] || exit 0
[[ -f "$MANIFEST" ]] || exit 0

# Marker file scoped to (cleanup logic version, plugin version). Bump the
# CLEANUP_LOGIC_VERSION whenever this script gains a new cleanup mode that
# previously-migrated users need to run — otherwise old markers from a prior
# logic version would short-circuit the new behavior. Plugin-version still
# participates so that future SKILL.md / plugin updates also trigger a fresh
# pass even at the same logic version.
#
# v1: skills cleanup only.
# v2: + unmarked plugin cleanup, + stale marketplace cache cleanup.
# v3: cache cleanup removed (cache is now the LEGITIMATE install path —
#     direct ~/.codex/plugins/<name>/ installs are always stale because Codex
#     never loaded plugins from there). Hook now removes ~/.codex/plugins/
#     <name>/ regardless of marker, since the marker came from the (broken)
#     prior --user install path.
CLEANUP_LOGIC_VERSION="v3"
PLUGIN_VERSION="$(awk -F'"' '/"version"/ {print $4; exit}' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")"
MARKER="$HOME/.codex/.gopher-ai-cleanup-${CLEANUP_LOGIC_VERSION}-${PLUGIN_VERSION}"
[[ -f "$MARKER" ]] && exit 0

# Detect a portable sha256 implementation. macOS ships `shasum -a 256` but not
# `sha256sum`; some minimal Linux installs and busybox-based systems ship
# `sha256sum` but not `shasum`. Use whichever is available so the migration
# actually runs on stock macOS (the majority case for gopher-ai users).
SHA256_CMD=""
if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA256_CMD="shasum -a 256"
elif command -v openssl >/dev/null 2>&1; then
    # `openssl dgst -sha256` prints "SHA2-256(file)= <hash>" or "(stdin)= <hash>";
    # we wrap it so the consumers downstream can `awk '{print $1}'` uniformly.
    SHA256_CMD="openssl_sha256_compat"
    openssl_sha256_compat() {
        openssl dgst -sha256 "$@" 2>/dev/null | awk '{print $NF, "-"}'
    }
fi
[[ -n "$SHA256_CMD" ]] || exit 0

for cmd in awk basename; do
    command -v "$cmd" >/dev/null 2>&1 || exit 0
done

# Wrap the chosen hash command so call sites stay uniform.
sha256_of() {
    if [[ "$SHA256_CMD" == "openssl_sha256_compat" ]]; then
        openssl_sha256_compat "$1" | awk '{print $1}'
    else
        $SHA256_CMD "$1" 2>/dev/null | awk '{print $1}'
    fi
}

# Read the SKILL.md frontmatter `name:` field. Returns empty if missing or
# malformed. Tolerant of single quotes, double quotes, and unquoted values.
skill_md_name() {
    local skill_md="$1"
    [[ -f "$skill_md" ]] || { echo ""; return; }
    awk '
        /^---[[:space:]]*$/ { fm++; next }
        fm == 1 && /^name:[[:space:]]*/ {
            sub(/^name:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
        fm >= 2 { exit }
    ' "$skill_md"
}

# Build the set of gopher-ai skill names from the manifest (column 2 of
# non-comment, non-blank lines).
KNOWN_SKILLS="$(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { print $2 }
' "$MANIFEST" | sort -u)"

[[ -n "$KNOWN_SKILLS" ]] || exit 0

# --- 1. Skills cleanup ----------------------------------------------------
# Walk candidates in ~/.codex/skills/ and remove those passing all three checks.
removed_skills=0
removed_skill_paths=""
if [[ -d "$SKILLS_HOME" ]]; then
    while IFS= read -r skill_name; do
        [[ -n "$skill_name" ]] || continue
        target="$SKILLS_HOME/$skill_name"
        [[ -d "$target" ]] || continue

        skill_md="$target/SKILL.md"
        [[ -f "$skill_md" ]] || continue

        # Check 1: frontmatter name matches directory name.
        fm_name="$(skill_md_name "$skill_md")"
        [[ "$fm_name" == "$skill_name" ]] || continue

        # Check 2: SKILL.md content hash matches a (hash, skill_name) pair we shipped.
        candidate_hash="$(sha256_of "$skill_md")"
        [[ -n "$candidate_hash" ]] || continue
        if ! awk -v target_hash="$candidate_hash" -v target_skill="$skill_name" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            $1 == target_hash && $2 == target_skill { found = 1; exit }
            END { exit (found ? 0 : 1) }
        ' "$MANIFEST"; then
            continue
        fi

        rm -rf "$target" 2>/dev/null && {
            removed_skill_paths="${removed_skill_paths}${target}\n"
            removed_skills=$((removed_skills + 1))
        }
    done <<<"$KNOWN_SKILLS"
fi

# --- 2. Unmarked plugin cleanup -------------------------------------------
# Walk ~/.codex/plugins/<name>/ for the seven plugin names we ship. Remove a
# directory only when ALL of these hold:
#   - directory name matches one of our seven plugin names
#   - NO .gopher-ai-installed marker file (we never touch marked installs)
#   - .codex-plugin/plugin.json exists
#   - plugin.json `name:` field matches the directory name
#   - plugin.json `author.email` is "support@gopherguides.com" — distinctive
#     to gopher-ai. A user-authored plugin that happens to share a name will
#     have a different (or missing) author email and be left alone.
# This pattern catches old README-era manual installs that pre-date the
# marker convention while keeping user-authored plugins safe.
removed_plugins=0
removed_plugin_paths=""
GOPHER_AI_AUTHOR_EMAIL="support@gopherguides.com"

# Extract a top-level JSON string field by name. Scoped to depth-1 keys so
# `name` returns the top-level plugin name, not `author.name`.
json_top_string() {
    local file="$1" field="$2"
    awk -v target="$field" '
        BEGIN { depth = 0; pending_key = "" }
        {
            line = $0
            while (length(line) > 0) {
                c = substr(line, 1, 1)
                line = substr(line, 2)
                if (c == "\"") {
                    tok = ""
                    while (length(line) > 0) {
                        cc = substr(line, 1, 1); line = substr(line, 2)
                        if (cc == "\\") { tok = tok substr(line, 1, 1); line = substr(line, 2) }
                        else if (cc == "\"") break
                        else tok = tok cc
                    }
                    if (depth == 1 && pending_key == target) {
                        print tok
                        exit
                    }
                    last_token = tok
                } else if (c == ":") {
                    pending_key = last_token
                } else if (c == "{") {
                    depth++; pending_key = ""
                } else if (c == "}") {
                    depth--
                } else if (c == ",") {
                    pending_key = ""
                }
            }
        }
    ' "$file" 2>/dev/null
}

# Extract author.email from a plugin.json. Walks the JSON token stream,
# tracking when we are inside the `author` object specifically — does not
# match the first `"email"` anywhere in the file (which would be wrong if
# any other object also has an email field).
json_author_email() {
    local file="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.author.email // ""' "$file" 2>/dev/null
        return
    fi
    awk '
        BEGIN { in_author = 0; depth = 0; author_depth = 0; pending_key = "" }
        {
            line = $0
            while (length(line) > 0) {
                c = substr(line, 1, 1)
                line = substr(line, 2)
                if (c == "\"") {
                    tok = ""
                    while (length(line) > 0) {
                        cc = substr(line, 1, 1); line = substr(line, 2)
                        if (cc == "\\") { tok = tok substr(line, 1, 1); line = substr(line, 2) }
                        else if (cc == "\"") break
                        else tok = tok cc
                    }
                    if (in_author && pending_key == "email") {
                        print tok
                        exit
                    }
                    last_token = tok
                } else if (c == ":") {
                    pending_key = last_token
                } else if (c == "{") {
                    depth++
                    if (pending_key == "author") { in_author = 1; author_depth = depth }
                    pending_key = ""
                } else if (c == "}") {
                    if (in_author && depth == author_depth) in_author = 0
                    depth--
                } else if (c == ",") {
                    pending_key = ""
                }
            }
        }
    ' "$file" 2>/dev/null
}

#
# A directory at ~/.codex/plugins/<plugin-name>/ is ALWAYS stale (regardless
# of marker) — we just learned that Codex never actually loaded plugins from
# there. The legitimate install path is the marketplace cache at
# ~/.codex/plugins/cache/gopher-ai/<plugin>/<commit-hash>/, populated by
# install-codex.sh --user. Earlier `--user` versions wrote a marker file
# alongside a direct install; that direct install was inert, so removing it
# only eliminates clutter and frees the directory name for the user.
if [[ -d "$PLUGINS_HOME" ]]; then
    for plugin_name in $KNOWN_PLUGINS; do
        target="$PLUGINS_HOME/$plugin_name"
        [[ -d "$target" ]] || continue

        # Three independent signals that this directory is gopher-ai cruft:
        #   - Has the marker file we used to write
        #   - plugin.json with our author.email
        #   - plugin.json with our top-level name
        # Any single signal is enough to remove. A user-authored plugin
        # sharing one of our names with a different author email AND no
        # marker survives all three checks.
        is_ours=false
        if [[ -f "$target/.gopher-ai-installed" ]]; then
            is_ours=true
        elif [[ -f "$target/.codex-plugin/plugin.json" ]]; then
            json_email="$(json_author_email "$target/.codex-plugin/plugin.json")"
            if [[ "$json_email" == "$GOPHER_AI_AUTHOR_EMAIL" ]]; then
                is_ours=true
            fi
        fi
        [[ "$is_ours" == "true" ]] || continue

        rm -rf "$target" 2>/dev/null && {
            removed_plugin_paths="${removed_plugin_paths}${target}\n"
            removed_plugins=$((removed_plugins + 1))
        }
    done
fi

# Always write the marker so we don't re-scan next session.
mkdir -p "$(dirname "$MARKER")" 2>/dev/null
: > "$MARKER" 2>/dev/null

if [[ "$removed_skills" -gt 0 || "$removed_plugins" -gt 0 ]]; then
    {
        if [[ "$removed_skills" -gt 0 ]]; then
            printf '🧹 gopher-ai: removed %d legacy Codex skill director%s from ~/.codex/skills/:\n' \
                "$removed_skills" "$([ "$removed_skills" -eq 1 ] && echo y || echo ies)"
            printf '%b' "$removed_skill_paths" | sed 's|^|  |'
        fi
        if [[ "$removed_plugins" -gt 0 ]]; then
            printf '🧹 gopher-ai: removed %d stale plugin director%s from ~/.codex/plugins/:\n' \
                "$removed_plugins" "$([ "$removed_plugins" -eq 1 ] && echo y || echo ies)"
            printf '%b' "$removed_plugin_paths" | sed 's|^|  |'
            printf '   (those were never loaded by Codex — the live install lives at\n'
            printf '   ~/.codex/plugins/cache/gopher-ai/. If you want gopher-ai globally,\n'
            printf '   run scripts/install-codex.sh --user.)\n'
        fi
    } >&2
fi

exit 0
