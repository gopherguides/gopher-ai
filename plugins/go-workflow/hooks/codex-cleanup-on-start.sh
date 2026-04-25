#!/bin/bash
# codex-cleanup-on-start.sh — SessionStart hook that auto-removes legacy
# gopher-ai skill files left in ~/.codex/skills/ from older `--user` installs.
#
# This makes the migration "just work" — users don't have to remember to run
# install-codex.sh --cleanup. It runs once per (user, plugin-version), gated by
# a marker file, so it's nearly free on subsequent sessions.
#
# Safety: a candidate is only removed when ALL of these hold:
#   1. The directory ~/.codex/skills/<name>/ matches a gopher-ai skill name.
#   2. The SKILL.md frontmatter `name:` field matches the directory name.
#   3. The SKILL.md sha256 matches a (hash, skill_name) pair in the shipped
#      legacy-skill-hashes.txt manifest.
# All three together make false-positive deletion essentially impossible.
#
# Exits 0 on all paths so it never blocks a session start. Errors are
# silenced; nothing prints unless a cleanup actually happened (visible to
# the user in the Claude Code transcript).

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MANIFEST="$PLUGIN_ROOT/hooks/legacy-skill-hashes.txt"
SKILLS_HOME="$HOME/.codex/skills"

# Fast-exit: nothing to clean.
[[ -d "$SKILLS_HOME" ]] || exit 0
[[ -f "$MANIFEST" ]] || exit 0

# Marker file scoped to plugin version. New gopher-ai versions trigger a
# fresh check (in case new skills were added that need migration too).
PLUGIN_VERSION="$(awk -F'"' '/"version"/ {print $4; exit}' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "unknown")"
MARKER="$HOME/.codex/.gopher-ai-cleanup-$PLUGIN_VERSION"
[[ -f "$MARKER" ]] && exit 0

# Don't depend on tools the user might not have. Need: sha256sum, awk, basename, rm.
for cmd in sha256sum awk basename; do
    command -v "$cmd" >/dev/null 2>&1 || exit 0
done

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

# Walk candidates and remove only those passing all three checks.
removed=0
candidates=""
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
    candidate_hash="$(sha256sum "$skill_md" 2>/dev/null | awk '{print $1}')"
    [[ -n "$candidate_hash" ]] || continue
    if ! awk -v target_hash="$candidate_hash" -v target_skill="$skill_name" '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        $1 == target_hash && $2 == target_skill { found = 1; exit }
        END { exit (found ? 0 : 1) }
    ' "$MANIFEST"; then
        continue
    fi

    # All checks passed — remove.
    rm -rf "$target" 2>/dev/null && {
        candidates="${candidates}${target}\n"
        removed=$((removed + 1))
    }
done <<<"$KNOWN_SKILLS"

# Always write the marker so we don't re-scan next session.
mkdir -p "$(dirname "$MARKER")" 2>/dev/null
: > "$MARKER" 2>/dev/null

if [[ "$removed" -gt 0 ]]; then
    {
        printf '🧹 gopher-ai: removed %d legacy Codex skill director%s from ~/.codex/skills/:\n' \
            "$removed" "$([ "$removed" -eq 1 ] && echo y || echo ies)"
        printf '%b' "$candidates" | sed 's|^|  |'
        printf '   (Codex now discovers gopher-ai via the plugin marketplace.)\n'
    } >&2
fi

exit 0
