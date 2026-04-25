#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/codex"
REPO_SLUG="${GOPHER_AI_REPO:-gopherguides/gopher-ai}"
REPO_REF="${GOPHER_AI_REF:-main}"
ARCHIVE_URL="${GOPHER_AI_ARCHIVE_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}}"
BOOTSTRAP_DIR=""

usage() {
    cat <<'EOF'
Usage:
  scripts/install-codex.sh --repo /path/to/repo
  scripts/install-codex.sh --cleanup [--yes]

gopher-ai is delivered to Codex as plugins. Codex discovers them automatically
when you run inside a repo that has .agents/plugins/marketplace.json (this repo
ships one). To make them available in another repo, use --repo.

Options:
  --repo PATH   Install plugins into PATH/plugins and merge entries into
                PATH/.agents/plugins/marketplace.json. Auto-cleans legacy
                ~/.codex/skills/ entries left over from older installs
                (with --yes semantics — assumes the user wants the migration).
  --cleanup     Remove legacy gopher-ai skills from ~/.codex/skills/ left over
                from the old --user mode. Lists candidates and prompts before
                deleting. Two ownership gates protect user-authored skills:
                (1) the SKILL.md frontmatter must have `name: <dirname>`, and
                (2) its content must hash-match a current or historical
                gopher-ai-shipped version of that file (via git history when
                this script runs from a clone, or just current sources in
                bootstrap mode). A user-authored skill at a generic name like
                `commit` or `ship` will fail the content check and be kept.
  --yes         Skip the interactive confirmation in --cleanup (used by
                install-all.sh and CI flows).
  --help        Show this help text

Notes:
  --user has been removed. The old mode copied skills into ~/.codex/skills/,
  which double-loaded them alongside the plugin marketplace and overflowed the
  Codex skill metadata budget. Run --cleanup once on machines that used --user
  before, then rely on the marketplace for skill discovery.
EOF
}

cleanup() {
    if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_DIR"
    fi
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
    if command -v git >/dev/null 2>&1; then
        local clone_url="https://github.com/${REPO_SLUG}.git"
        extracted_root="$BOOTSTRAP_DIR/gopher-ai"
        if ! git clone --quiet --branch "$REPO_REF" --single-branch \
                "$clone_url" "$extracted_root" 2>/dev/null; then
            extracted_root=""  # clone failed, fall through
        fi
    fi

    if [[ -z "$extracted_root" ]]; then
        require_cmd curl
        require_cmd tar
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
    local manifest="$ROOT_DIR/scripts/legacy-skill-hashes.txt"
    if [[ -f "$manifest" ]]; then
        # The manifest stores one hash per non-comment line. Use awk for a
        # single pass without spawning grep.
        if awk -v target="$candidate_hash" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            $1 == target { found = 1; exit }
            END { exit (found ? 0 : 1) }
        ' "$manifest"; then
            return 0
        fi
    fi

    # 3. Live git history (covers blobs committed after the manifest was regen'd).
    if (cd "$ROOT_DIR" && [[ -d .git ]]) 2>/dev/null; then
        local blobs
        blobs="$(cd "$ROOT_DIR" && git rev-list --objects --all 2>/dev/null \
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
            cat >&2 <<'EOF'
error: --user mode has been removed.

The old --user mode copied skills into ~/.codex/skills/, which conflicted
with the plugin marketplace and overflowed Codex's skill metadata budget.
gopher-ai is now delivered as Codex plugins only.

To migrate:
  1. ./scripts/install-codex.sh --cleanup     # remove legacy ~/.codex/skills/ entries
  2. Run codex inside a repo that has .agents/plugins/marketplace.json
     (this repo ships one), or use --repo to add the marketplace to another repo.
EOF
            exit 1
            ;;
        --cleanup)
            bootstrap_repo
            local assume_yes=false
            if [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]]; then
                assume_yes=true
            fi
            cleanup_legacy_user_skills "$assume_yes"
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
