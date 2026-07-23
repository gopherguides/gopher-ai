#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/codex"
REPO_SLUG="${GOPHER_AI_REPO:-gopherguides/gopher-ai}"
REPO_REF="${GOPHER_AI_REF:-main}"
ARCHIVE_URL="${GOPHER_AI_ARCHIVE_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}}"
BOOTSTRAP_DIR=""
CACHE_BACKUP_DIRS=()
LEGACY_MARKETPLACE_PATH=""
LEGACY_MARKETPLACE_BACKUP_DIR=""

usage() {
    cat <<'EOF'
Usage:
  scripts/install-codex.sh --user
  scripts/install-codex.sh --repo /path/to/repo
  scripts/install-codex.sh --cleanup [--yes]
  scripts/install-codex.sh --prune-cache [--yes]

gopher-ai for Codex can be installed in two ways:

  --user        Install plugins globally through the public Codex plugin CLI so
                they load in EVERY Codex session, regardless of the working
                directory. Codex publishes versioned roots before activation.
                Previously published roots are retained for active sessions.
                Also removes legacy ~/.codex/skills/ entries left over from
                older installs (with --yes semantics — assumes the user wants
                the migration).

  --repo PATH   Install plugins into PATH/plugins and merge entries into
                PATH/.agents/plugins/marketplace.json. Use this for project-
                scoped installs where you want the plugins to load only when
                running Codex inside that repo. Also runs the legacy
                ~/.codex/skills/ cleanup.

  --cleanup     Remove legacy gopher-ai skills from ~/.codex/skills/ left over
                from the old `--user` mode (which copied skills there). Two
                ownership gates protect user-authored skills: (1) the SKILL.md
                frontmatter must have `name: <dirname>`, and (2) its content
                must hash-match a gopher-ai-shipped version of that file via
                the bundled scripts/legacy-skill-hashes.txt manifest. A user-
                authored skill at a generic name like `commit` or `ship` will
                fail the content check and be kept.

  --prune-cache Remove superseded Gopher AI marketplace cache roots. Close all
                Codex sessions before running this command; active sessions
                retain absolute paths into these roots. The current plugin
                version is always kept.

  --yes         Skip interactive confirmation in --cleanup or --prune-cache.
  --help        Show this help text
EOF
}

restore_legacy_user_marketplace() {
    [[ -n "$LEGACY_MARKETPLACE_PATH" ]] || return 0
    local backup_file="$LEGACY_MARKETPLACE_BACKUP_DIR/marketplace.json"
    if [[ -e "$backup_file" || -L "$backup_file" ]]; then
        mkdir -p "$(dirname "$LEGACY_MARKETPLACE_PATH")"
        mv "$backup_file" "$LEGACY_MARKETPLACE_PATH"
    fi
    [[ -z "$LEGACY_MARKETPLACE_BACKUP_DIR" ]] || rm -rf "$LEGACY_MARKETPLACE_BACKUP_DIR"
    LEGACY_MARKETPLACE_PATH=""
    LEGACY_MARKETPLACE_BACKUP_DIR=""
}

cleanup() {
    restore_legacy_user_marketplace
    if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_DIR"
    fi
    local cache_backup_dir
    for cache_backup_dir in "${CACHE_BACKUP_DIRS[@]-}"; do
        [[ -n "$cache_backup_dir" ]] || continue
        if [[ -d "$cache_backup_dir" ]]; then
            rm -rf "$cache_backup_dir"
        fi
    done
}

trap cleanup EXIT

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: required command not found: $cmd" >&2
        exit 1
    fi
}

bootstrap_repo() {
    if [[ -f "$ROOT_DIR/scripts/build-universal.sh" ]]; then
        return
    fi

    BOOTSTRAP_DIR="$(mktemp -d)"
    local extracted_root=""

    # Prefer git clone when available — gives the cleanup logic full history
    # access. Falls back to curl|tar if git is missing, in which case the
    # shipped legacy-skill-hashes.txt manifest covers ownership verification.
    #
    # When the caller explicitly sets GOPHER_AI_ARCHIVE_URL (PR tarballs, local
    # mirrors, the test suite), honor it instead of clone — overriding the
    # source URL has no effect if we always clone the default repo.
    if [[ -z "${GOPHER_AI_ARCHIVE_URL:-}" ]] && command -v git >/dev/null 2>&1; then
        local clone_url="https://github.com/${REPO_SLUG}.git"
        extracted_root="$BOOTSTRAP_DIR/gopher-ai"
        echo "Bootstrap source: git clone $clone_url@$REPO_REF" >&2
        if ! git clone --quiet --branch "$REPO_REF" --single-branch \
                "$clone_url" "$extracted_root" 2>/dev/null; then
            # Remove the partial clone so the tar fallback's `find` doesn't pick
            # this broken directory over the freshly-extracted archive.
            rm -rf "$extracted_root"
            extracted_root=""
        fi
    fi

    if [[ -z "$extracted_root" ]]; then
        require_cmd curl
        require_cmd tar
        echo "Bootstrap source: curl $ARCHIVE_URL" >&2
        curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$BOOTSTRAP_DIR"
        extracted_root="$(find "$BOOTSTRAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    fi

    if [[ -z "$extracted_root" || ! -f "$extracted_root/scripts/build-universal.sh" ]]; then
        echo "error: failed to bootstrap gopher-ai from $REPO_SLUG@$REPO_REF" >&2
        exit 1
    fi

    ROOT_DIR="$extracted_root"
    DIST_DIR="$ROOT_DIR/dist/codex"
}

ensure_dist() {
    bootstrap_repo

    if [[ ! -f "$DIST_DIR/plugins/marketplace.json" ]]; then
        "$ROOT_DIR/scripts/build-universal.sh"
    fi
}

merge_marketplace() {
    local existing="$1"
    local incoming="$2"
    local merged="$3"

    if [[ -f "$existing" ]]; then
        jq -s '
            .[0] as $old | .[1] as $new |
            {
              name: ($old.name // $new.name // "local-plugins"),
              interface: ($old.interface // $new.interface // {"displayName":"Local Plugins"}),
              plugins: (
                (($old.plugins // [])
                  | map(select(.name as $name | (($new.plugins // []) | map(.name) | index($name) | not))))
                + ($new.plugins // [])
              )
            }
        ' "$existing" "$incoming" >"$merged"
    else
        cp "$incoming" "$merged"
    fi
}

# Reads the SKILL.md frontmatter `name:` field. Returns empty if missing.
# Tolerant of single quotes, double quotes, and unquoted values; does not
# require a YAML parser.
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

# Returns 0 if the candidate file's content matches some historical or current
# version of a gopher-ai SKILL.md. Three sources are checked, in order:
#
# 1. Current source files (plugins/*/skills/<name>/SKILL.md) — always available.
# 2. The shipped manifest (scripts/legacy-skill-hashes.txt) — sha256 hashes of
#    every SKILL.md blob this repo has ever committed. Built by
#    scripts/regen-legacy-hashes.sh and committed alongside the source. This
#    is what makes --cleanup work in curl-piped bootstrap mode (where there
#    is no .git/ directory at install time).
# 3. Live git history when .git/ is available — covers commits made after
#    the manifest was last regenerated.
file_matches_known_skill_content() {
    local skill_name="$1"
    local candidate_file="$2"
    [[ -f "$candidate_file" ]] || return 1

    local candidate_hash
    candidate_hash="$(sha256sum "$candidate_file" 2>/dev/null | awk '{print $1}')"
    [[ -n "$candidate_hash" ]] || return 1

    # 1. Current source files.
    local p
    for p in "$ROOT_DIR"/plugins/*/skills/"$skill_name"/SKILL.md; do
        [[ -f "$p" ]] || continue
        local h
        h="$(sha256sum "$p" 2>/dev/null | awk '{print $1}')"
        [[ "$h" == "$candidate_hash" ]] && return 0
    done

    # 2. Shipped manifest of historical hashes (works without git history).
    # Each non-comment line is "<sha256> <skill_name>" — both fields must
    # match so a hash from skill A is not accepted as proof of ownership for
    # a candidate in skill B's directory.
    local manifest="$ROOT_DIR/scripts/legacy-skill-hashes.txt"
    if [[ -f "$manifest" ]]; then
        if awk -v target_hash="$candidate_hash" -v target_skill="$skill_name" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            $1 == target_hash && $2 == target_skill { found = 1; exit }
            END { exit (found ? 0 : 1) }
        ' "$manifest"; then
            return 0
        fi
    fi

    # 3. Live git history (covers blobs committed after the manifest was regen'd).
    if (cd "$ROOT_DIR" && [[ -d .git ]]) 2>/dev/null; then
        local blobs
        blobs="$(cd "$ROOT_DIR" && git rev-list --objects HEAD 2>/dev/null \
            | awk -v name="$skill_name" '$2 ~ "^plugins/[^/]+/skills/"name"/SKILL.md$" {print $1}' \
            | sort -u)"
        if [[ -n "$blobs" ]]; then
            local blob blob_hash
            while IFS= read -r blob; do
                [[ -n "$blob" ]] || continue
                blob_hash="$(cd "$ROOT_DIR" && git cat-file blob "$blob" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
                [[ "$blob_hash" == "$candidate_hash" ]] && return 0
            done <<<"$blobs"
        fi
    fi
    return 1
}

cleanup_legacy_user_skills() {
    local assume_yes="${1:-false}"
    local skills_home="$HOME/.codex/skills"
    if [[ ! -d "$skills_home" ]]; then
        echo "no ~/.codex/skills/ directory — nothing to clean up"
        return 0
    fi

    local has_git_history=false
    if (cd "$ROOT_DIR" && [[ -d .git ]]) 2>/dev/null; then
        has_git_history=true
    fi

    # Build candidate list: dirs in ~/.codex/skills/ whose name matches a
    # gopher-ai skill, whose SKILL.md frontmatter `name:` confirms it, AND
    # whose SKILL.md content matches a historical or current gopher-ai shipped
    # version. The content check is the hard ownership signal — without it,
    # generic names like `commit` or `ship` would falsely match user-authored
    # skills that happen to share a name and define `name:` matching the dir.
    local candidates=()
    local skipped_name_mismatch=()
    local skipped_content_mismatch=()
    local skill_dir
    for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name target skill_md
        skill_name="$(basename "$skill_dir")"
        target="$skills_home/$skill_name"
        [[ -d "$target" ]] || continue
        skill_md="$target/SKILL.md"

        local fm_name
        fm_name="$(skill_md_name "$skill_md")"
        if [[ "$fm_name" != "$skill_name" ]]; then
            skipped_name_mismatch+=("$target (frontmatter name: '${fm_name:-<missing>}')")
            continue
        fi
        if file_matches_known_skill_content "$skill_name" "$skill_md"; then
            candidates+=("$target")
        else
            skipped_content_mismatch+=("$target")
        fi
    done

    if [[ ${#skipped_name_mismatch[@]} -gt 0 ]]; then
        echo "skipping (frontmatter name doesn't match directory — not gopher-ai-installed):"
        local entry
        for entry in "${skipped_name_mismatch[@]}"; do
            echo "  $entry"
        done
    fi

    if [[ ${#skipped_content_mismatch[@]} -gt 0 ]]; then
        echo "skipping (SKILL.md content does not match any gopher-ai-shipped version — likely user-authored):"
        local entry
        for entry in "${skipped_content_mismatch[@]}"; do
            echo "  $entry"
        done
        if [[ "$has_git_history" == "false" ]] && [[ ! -f "$ROOT_DIR/scripts/legacy-skill-hashes.txt" ]]; then
            echo "  (note: running without git history and no legacy-skill-hashes.txt manifest"
            echo "   was found; only current sources were checked. To migrate older --user"
            echo "   installs, clone the repo and run --cleanup from there.)"
        fi
    fi

    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "no legacy gopher-ai skills found in $skills_home"
        return 0
    fi

    echo "found ${#candidates[@]} legacy gopher-ai skill(s) to remove:"
    local target
    for target in "${candidates[@]}"; do
        echo "  $target"
    done

    if [[ "$assume_yes" != "true" ]]; then
        if [[ ! -t 0 ]]; then
            echo ""
            echo "stdin is not a terminal — re-run with --yes to confirm removal."
            echo "(install-all.sh passes --yes automatically.)"
            return 1
        fi
        local answer=""
        printf "remove these directories? [y/N] "
        read -r answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) echo "aborted — nothing removed."; return 0 ;;
        esac
    fi

    local removed=0
    for target in "${candidates[@]}"; do
        rm -rf "${target:?}"
        echo "removed: $target"
        removed=$((removed + 1))
    done
    echo "cleaned up $removed legacy skill director$([ "$removed" -eq 1 ] && echo "y" || echo "ies")"
}

build_repo_marketplace() {
    local output_file="$1"

    jq '
        .plugins |= map(
            .source.path |= sub("^\\./\\.codex/plugins/"; "./plugins/")
        )
    ' "$DIST_DIR/plugins/marketplace.json" >"$output_file"
}

# Returns 0 if the directory at $1 is safe to overwrite as a gopher-ai install:
#   - empty or missing
#   - has our marker (prior --user install)
#   - has plugin.json with author.email == support@gopherguides.com (legacy
#     manual install from old README — still ours to replace)
# Returns 1 (refuse to overwrite) otherwise — e.g. a user-authored plugin that
# happens to share one of our names but has a different author email.
target_is_safe_to_overwrite() {
    local target="$1"
    [[ -d "$target" ]] || return 0
    [[ -f "$target/.gopher-ai-installed" ]] && return 0
    local plugin_json="$target/.codex-plugin/plugin.json"
    [[ -f "$plugin_json" ]] || return 0  # not a Codex plugin — empty/leftover, safe
    local owner_email
    owner_email="$(plugin_json_author_email "$plugin_json")"
    [[ "$owner_email" == "support@gopherguides.com" ]]
}

# Extract author.email from a plugin.json. Prefers jq (precise); falls back to
# a scoped awk parser that walks tokens to find author -> email — does NOT
# match the first "email" anywhere in the file, which would be wrong if any
# other object in the JSON also has an email field.
plugin_json_author_email() {
    local f="$1"
    [[ -f "$f" ]] || { echo ""; return; }
    if command -v jq >/dev/null 2>&1; then
        jq -r '.author.email // ""' "$f" 2>/dev/null
        return
    fi
    awk '
        BEGIN { in_author = 0; depth = 0; author_depth = 0 }
        {
            line = $0
            while (length(line) > 0) {
                c = substr(line, 1, 1)
                line = substr(line, 2)
                if (c == "\"") {
                    # Read a quoted token, honoring backslash escapes.
                    tok = ""
                    while (length(line) > 0) {
                        cc = substr(line, 1, 1)
                        line = substr(line, 2)
                        if (cc == "\\") {
                            tok = tok substr(line, 1, 1)
                            line = substr(line, 2)
                        } else if (cc == "\"") {
                            break
                        } else {
                            tok = tok cc
                        }
                    }
                    last_key_token = tok
                } else if (c == ":") {
                    pending_key = last_key_token
                } else if (c == "{") {
                    depth++
                    if (pending_key == "author") {
                        in_author = 1
                        author_depth = depth
                    }
                    pending_key = ""
                } else if (c == "}") {
                    if (in_author && depth == author_depth) in_author = 0
                    depth--
                } else if (in_author && pending_key == "email" && c ~ /[^[:space:]]/) {
                    # Already past the colon; expect the next quoted token to
                    # be the value. Re-prepend so the next iteration parses it.
                    line = c line
                    sub(/^[[:space:]]*"/, "", line)
                    val = ""
                    while (length(line) > 0) {
                        cc = substr(line, 1, 1)
                        line = substr(line, 2)
                        if (cc == "\\") { val = val substr(line, 1, 1); line = substr(line, 2) }
                        else if (cc == "\"") break
                        else val = val cc
                    }
                    print val
                    exit
                }
            }
        }
    ' "$f"
}

cache_root_matches_plugin() {
    local source_root="$1"
    local cache_root="$2"
    [[ -d "$cache_root" ]] || return 1

    local source_file relative cache_file
    while IFS= read -r -d '' source_file; do
        relative="${source_file#"$source_root"/}"
        case "$relative" in
            .claude-plugin/*) continue ;;
        esac
        cache_file="$cache_root/$relative"
        [[ -f "$cache_file" ]] || return 1
        cmp -s "$source_file" "$cache_file" || return 1
        if [[ -x "$source_file" && ! -x "$cache_file" ]]; then
            return 1
        fi
    done < <(find "$source_root" -type f -print0)
    return 0
}

backup_published_plugin_roots() {
    local marketplace_cache="$HOME/.codex/plugins/cache/gopher-ai"
    CACHE_BACKUP_DIR=""
    [[ -d "$marketplace_cache" ]] || return 0

    local temp_base="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
    CACHE_BACKUP_DIR="$(mktemp -d "${temp_base%/}/gopher-ai-codex-cache.XXXXXX")"
    CACHE_BACKUP_DIRS+=("$CACHE_BACKUP_DIR")

    local plugin_cache plugin_name cache_root
    for plugin_cache in "$marketplace_cache"/*; do
        [[ -d "$plugin_cache" ]] || continue
        plugin_name="$(basename "$plugin_cache")"
        mkdir -p "$CACHE_BACKUP_DIR/$plugin_name"
        for cache_root in "$plugin_cache"/*; do
            [[ -d "$cache_root" ]] || continue
            cp -R -p "$cache_root" "$CACHE_BACKUP_DIR/$plugin_name/"
        done
    done
}

restore_removed_plugin_roots() {
    local backup_dir="$1"
    [[ -n "$backup_dir" && -d "$backup_dir" ]] || return 0

    local plugin_backup plugin_name plugin_cache backup_root version target_root
    for plugin_backup in "$backup_dir"/*; do
        [[ -d "$plugin_backup" ]] || continue
        plugin_name="$(basename "$plugin_backup")"
        plugin_cache="$HOME/.codex/plugins/cache/gopher-ai/$plugin_name"
        for backup_root in "$plugin_backup"/*; do
            [[ -d "$backup_root" ]] || continue
            version="$(basename "$backup_root")"
            mkdir -p "$plugin_cache"
            target_root="$plugin_cache/$version"
            rm -rf "${target_root:?}"
            cp -R -p "$backup_root" "$target_root"
        done
    done
    rm -rf "$backup_dir"
}

codex_plugin_names_json() {
    local plugin_dir
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
        basename "$plugin_dir"
    done | jq -R . | jq -s .
}

prepare_legacy_user_marketplace_migration() {
    local candidate="$HOME/.agents/plugins/marketplace.json"
    [[ -e "$candidate" || -L "$candidate" ]] || return 0

    if ! jq -e . "$candidate" >/dev/null 2>&1; then
        echo "error: preserved invalid marketplace file: $candidate" >&2
        echo "       move or repair it before installing gopher-ai." >&2
        return 1
    fi

    local marketplace_name
    marketplace_name="$(jq -r '.name // empty' "$candidate")"
    [[ "$marketplace_name" == "gopher-ai" ]] || return 0

    local allowed_plugins
    allowed_plugins="$(codex_plugin_names_json)"
    if ! jq -e --argjson allowed "$allowed_plugins" '
        (.plugins | type == "array" and length > 0) and
        all(.plugins[];
            .name as $plugin_name |
            ($plugin_name | type == "string") and
            ($allowed | index($plugin_name) != null) and
            .source.source == "local" and
            .source.path == ("./.codex/plugins/" + $plugin_name)
        )
    ' "$candidate" >/dev/null; then
        echo "error: preserved marketplace because ownership could not be proven: $candidate" >&2
        echo "       remove or rename the conflicting gopher-ai marketplace, then retry." >&2
        return 1
    fi

    local temp_base="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
    LEGACY_MARKETPLACE_BACKUP_DIR="$(mktemp -d "${temp_base%/}/gopher-ai-codex-marketplace.XXXXXX")"
    LEGACY_MARKETPLACE_PATH="$candidate"
    mv "$candidate" "$LEGACY_MARKETPLACE_BACKUP_DIR/marketplace.json"
    echo "migrating legacy Codex marketplace: $candidate"
}

commit_legacy_user_marketplace_migration() {
    [[ -z "$LEGACY_MARKETPLACE_BACKUP_DIR" ]] || rm -rf "$LEGACY_MARKETPLACE_BACKUP_DIR"
    LEGACY_MARKETPLACE_PATH=""
    LEGACY_MARKETPLACE_BACKUP_DIR=""
}

install_user_plugins() {
    require_cmd codex
    if ! codex plugin add --help >/dev/null 2>&1; then
        echo "error: installed Codex CLI does not support 'codex plugin add'." >&2
        echo "       upgrade Codex, then retry --user." >&2
        return 1
    fi

    prepare_legacy_user_marketplace_migration

    local marketplaces
    if ! marketplaces="$(codex plugin marketplace list --json 2>/dev/null)"; then
        echo "error: could not list configured Codex plugin marketplaces." >&2
        return 1
    fi

    backup_published_plugin_roots
    local cache_backup_dir="$CACHE_BACKUP_DIR"
    local marketplace_status=0
    set +e
    if jq -e '.marketplaces[]? | select(.name == "gopher-ai" and .marketplaceSource != null)' \
            >/dev/null <<<"$marketplaces"; then
        echo "marketplace already registered — upgrading..."
        codex plugin marketplace upgrade gopher-ai 2>&1 | sed 's/^/  /'
        marketplace_status=${PIPESTATUS[0]}
    else
        echo "registering gopher-ai marketplace..."
        codex plugin marketplace add "$REPO_SLUG" --ref "$REPO_REF" 2>&1 | sed 's/^/  /'
        marketplace_status=${PIPESTATUS[0]}
    fi
    set -e
    if [[ "$marketplace_status" -ne 0 ]]; then
        restore_removed_plugin_roots "$cache_backup_dir"
        return "$marketplace_status"
    fi

    local installed=0
    local plugin_dir
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
        local plugin_name
        plugin_name="$(basename "$plugin_dir")"
        echo "installing $plugin_name@gopher-ai..."
        local add_status=0
        set +e
        codex plugin add "${plugin_name}@gopher-ai" 2>&1 | sed 's/^/  /'
        add_status=${PIPESTATUS[0]}
        set -e
        if [[ "$add_status" -ne 0 ]]; then
            restore_removed_plugin_roots "$cache_backup_dir"
            return "$add_status"
        fi
        installed=$((installed + 1))
    done
    restore_removed_plugin_roots "$cache_backup_dir"
    commit_legacy_user_marketplace_migration

    if [[ "$installed" -eq 0 ]]; then
        echo "error: no Codex-capable plugins found in $ROOT_DIR/plugins." >&2
        return 1
    fi

    local removed_legacy=0
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
        local plugin_name
        plugin_name="$(basename "$plugin_dir")"
        local legacy="$HOME/.codex/plugins/$plugin_name"
        if [[ -d "$legacy" ]]; then
            if [[ -f "$legacy/.gopher-ai-installed" ]]; then
                rm -rf "$legacy"
                removed_legacy=$((removed_legacy + 1))
            elif [[ -f "$legacy/.codex-plugin/plugin.json" ]]; then
                local owner_email
                owner_email="$(plugin_json_author_email "$legacy/.codex-plugin/plugin.json")"
                if [[ "$owner_email" == "support@gopherguides.com" ]]; then
                    rm -rf "$legacy"
                    removed_legacy=$((removed_legacy + 1))
                fi
            fi
        fi
    done
    if [[ "$removed_legacy" -gt 0 ]]; then
        echo "removed $removed_legacy legacy direct-install plugin director$([ "$removed_legacy" -eq 1 ] && echo "y" || echo "ies")"
        echo "  (those were never loaded by Codex — only the marketplace cache is)"
    fi

    echo ""
    echo "installed $installed plugin(s) through the Codex plugin CLI."
    echo "Restart Codex; gopher-ai skills will load globally."
}

prune_user_plugin_cache() {
    local assume_yes="${1:-false}"
    local cache_root="$HOME/.codex/plugins/cache/gopher-ai"

    if [[ ! -d "$cache_root" ]]; then
        echo "no Gopher AI Codex cache found — nothing to prune"
        return 0
    fi

    local candidates=()
    local deferred=()
    local plugin_cache plugin_name plugin_source plugin_manifest current_version current_root current_ready cache_entry
    for plugin_cache in "$cache_root"/*; do
        [[ -d "$plugin_cache" ]] || continue
        plugin_name="$(basename "$plugin_cache")"
        plugin_source="$ROOT_DIR/plugins/$plugin_name"
        plugin_manifest="$plugin_source/.codex-plugin/plugin.json"
        current_version=""
        if [[ -f "$plugin_manifest" ]]; then
            current_version="$(jq -r '.version // empty' "$plugin_manifest")"
        fi
        current_root="$plugin_cache/$current_version"
        current_ready=false
        if [[ -n "$current_version" ]] \
            && cache_root_matches_plugin "$plugin_source" "$current_root"; then
            current_ready=true
        elif [[ -n "$current_version" ]]; then
            deferred+=("$plugin_cache")
        fi
        for cache_entry in "$plugin_cache"/* "$plugin_cache"/.[!.]* "$plugin_cache"/..?*; do
            [[ -e "$cache_entry" || -L "$cache_entry" ]] || continue
            if [[ -n "$current_version" ]]; then
                if [[ "$current_ready" == "true" && "$cache_entry" == "$current_root" ]]; then
                    continue
                fi
                if [[ "$current_ready" != "true" && "$cache_entry" != "$current_root" \
                    && "$(basename "$cache_entry")" != ".${current_version}.tmp."* ]]; then
                    continue
                fi
            fi
            candidates+=("$cache_entry")
        done
    done

    if [[ ${#candidates[@]} -eq 0 ]]; then
        echo "no superseded Gopher AI Codex cache roots found"
        if [[ ${#deferred[@]} -gt 0 ]]; then
            echo "latest roots are missing or incomplete; retained older roots. Run --user, then prune again."
        fi
        return 0
    fi

    echo "close all Codex sessions before removing superseded cache roots:"
    local candidate
    for candidate in "${candidates[@]}"; do
        echo "  $candidate"
    done

    if [[ "$assume_yes" != "true" ]]; then
        if [[ ! -t 0 ]]; then
            echo ""
            echo "stdin is not a terminal — close all Codex sessions, then re-run with --yes."
            return 1
        fi
        local answer=""
        printf "all Codex sessions are closed; remove these roots? [y/N] "
        read -r answer
        case "$answer" in
            [Yy]|[Yy][Ee][Ss]) ;;
            *) echo "aborted — nothing removed."; return 0 ;;
        esac
    fi

    local removed=0
    for candidate in "${candidates[@]}"; do
        rm -rf "${candidate:?}"
        echo "removed: $candidate"
        removed=$((removed + 1))
    done
    echo "pruned $removed superseded cache root$([ "$removed" -eq 1 ] || echo "s")"
    if [[ ${#deferred[@]} -gt 0 ]]; then
        echo "retained older roots for plugins without a complete latest root. Run --user, then prune again."
    fi
}

copy_repo_plugins() {
    local target_repo="$1"
    mkdir -p "$target_repo/plugins"

    local plugin_dir
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        local plugin_name
        plugin_name="$(basename "$plugin_dir")"
        if [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]]; then
            rm -rf "${target_repo:?}/plugins/$plugin_name"
            cp -R "$plugin_dir" "$target_repo/plugins/"
            echo "installed plugin: $target_repo/plugins/$plugin_name"
        fi
    done
}

write_repo_marketplace() {
    local target_repo="$1"
    local marketplace_dir="$target_repo/.agents/plugins"
    local marketplace_file="$marketplace_dir/marketplace.json"
    local incoming_file
    local merged_file

    incoming_file="$(mktemp)"
    merged_file="$(mktemp)"

    mkdir -p "$marketplace_dir"
    build_repo_marketplace "$incoming_file"
    merge_marketplace "$marketplace_file" "$incoming_file" "$merged_file"
    mv "$merged_file" "$marketplace_file"
    rm -f "$incoming_file"
    echo "updated marketplace: $marketplace_file"
}

main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --user)
            require_cmd jq
            bootstrap_repo
            install_user_plugins
            # --user is itself an explicit migration action; auto-confirm
            # the legacy ~/.codex/skills/ cleanup that runs alongside it.
            cleanup_legacy_user_skills "true"
            ;;
        --cleanup)
            bootstrap_repo
            local assume_yes=false
            if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
                assume_yes=true
            fi
            cleanup_legacy_user_skills "$assume_yes"
            ;;
        --prune-cache)
            require_cmd jq
            bootstrap_repo
            local assume_yes=false
            if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
                assume_yes=true
            fi
            prune_user_plugin_cache "$assume_yes"
            ;;
        --repo)
            if [[ $# -lt 2 ]]; then
                echo "error: --repo requires a target path" >&2
                exit 1
            fi
            require_cmd jq
            ensure_dist
            local target_repo
            target_repo="$(cd "$2" && pwd)"
            copy_repo_plugins "$target_repo"
            write_repo_marketplace "$target_repo"
            # --repo is itself an explicit migration action; auto-confirm cleanup.
            cleanup_legacy_user_skills "true"
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
