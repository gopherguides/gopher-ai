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
  scripts/install-codex.sh --cleanup

gopher-ai is delivered to Codex as plugins. Codex discovers them automatically
when you run inside a repo that has .agents/plugins/marketplace.json (this repo
ships one). To make them available in another repo, use --repo.

Options:
  --repo PATH   Install plugins into PATH/plugins and merge entries into
                PATH/.agents/plugins/marketplace.json. Auto-cleans legacy
                ~/.codex/skills/ entries left over from older installs.
  --cleanup     Remove legacy gopher-ai skills from ~/.codex/skills/ that were
                installed by the old --user mode. Safe — only removes skill
                directory names that match this repo's plugin skills.
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

    require_cmd curl
    require_cmd tar

    BOOTSTRAP_DIR="$(mktemp -d)"
    curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$BOOTSTRAP_DIR"

    local extracted_root
    extracted_root="$(find "$BOOTSTRAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "$extracted_root" || ! -f "$extracted_root/scripts/build-universal.sh" ]]; then
        echo "error: failed to bootstrap gopher-ai from $ARCHIVE_URL" >&2
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

cleanup_legacy_user_skills() {
    local skills_home="$HOME/.codex/skills"
    if [[ ! -d "$skills_home" ]]; then
        echo "no ~/.codex/skills/ directory — nothing to clean up"
        return 0
    fi

    local removed=0
    local skill_dir
    for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
        [[ -d "$skill_dir" ]] || continue
        local skill_name
        skill_name="$(basename "$skill_dir")"
        local target="$skills_home/$skill_name"
        if [[ -d "$target" ]]; then
            rm -rf "${target:?}"
            echo "removed legacy skill: $target"
            removed=$((removed + 1))
        fi
    done

    if [[ "$removed" -eq 0 ]]; then
        echo "no legacy gopher-ai skills found in $skills_home"
    else
        echo "cleaned up $removed legacy skill directories"
    fi
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
    require_cmd jq

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
            cleanup_legacy_user_skills
            ;;
        --repo)
            if [[ $# -lt 2 ]]; then
                echo "error: --repo requires a target path" >&2
                exit 1
            fi
            ensure_dist
            local target_repo
            target_repo="$(cd "$2" && pwd)"
            copy_repo_plugins "$target_repo"
            write_repo_marketplace "$target_repo"
            cleanup_legacy_user_skills
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
