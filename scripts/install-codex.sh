#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/codex"

usage() {
    cat <<'EOF'
Usage:
  scripts/install-codex.sh --user
  scripts/install-codex.sh --repo /path/to/repo

Installs or updates gopher-ai Codex plugins using the current plugin-based layout.

Options:
  --user        Install into ~/.codex/plugins and merge entries into ~/.agents/plugins/marketplace.json
  --repo PATH   Install into PATH/plugins and merge entries into PATH/.agents/plugins/marketplace.json
  --help        Show this help text
EOF
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "error: required command not found: $cmd" >&2
        exit 1
    fi
}

ensure_dist() {
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

copy_user_plugins() {
    local plugins_home="$HOME/.codex/plugins"
    mkdir -p "$plugins_home"

    local plugin_path
    for plugin_path in "$DIST_DIR"/plugins/*; do
        [[ -d "$plugin_path" ]] || continue
        local plugin_name
        plugin_name="$(basename "$plugin_path")"
        rm -rf "${plugins_home:?}/$plugin_name"
        cp -R "$plugin_path" "$plugins_home/"
        echo "installed plugin: $plugins_home/$plugin_name"
    done
}

write_user_marketplace() {
    local marketplace_dir="$HOME/.agents/plugins"
    local marketplace_file="$marketplace_dir/marketplace.json"
    local tmp_file
    tmp_file="$(mktemp)"

    mkdir -p "$marketplace_dir"
    merge_marketplace "$marketplace_file" "$DIST_DIR/plugins/marketplace.json" "$tmp_file"
    mv "$tmp_file" "$marketplace_file"
    echo "updated marketplace: $marketplace_file"
}

build_repo_marketplace() {
    local output_file="$1"

    jq -n '
        {
          name: "gopher-ai",
          interface: { displayName: "Gopher AI" },
          plugins: [
            {
              name: "go-workflow",
              source: { source: "local", path: "./plugins/go-workflow" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Development"
            },
            {
              name: "go-dev",
              source: { source: "local", path: "./plugins/go-dev" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Development"
            },
            {
              name: "gopher-guides",
              source: { source: "local", path: "./plugins/gopher-guides" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Development"
            },
            {
              name: "llm-tools",
              source: { source: "local", path: "./plugins/llm-tools" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Productivity"
            },
            {
              name: "go-web",
              source: { source: "local", path: "./plugins/go-web" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Development"
            },
            {
              name: "tailwind",
              source: { source: "local", path: "./plugins/tailwind" },
              policy: { installation: "AVAILABLE", authentication: "ON_USE" },
              category: "Development"
            }
          ]
        }
    ' >"$output_file"
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
            ensure_dist
            copy_user_plugins
            write_user_marketplace
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
            ;;
        *)
            usage >&2
            exit 1
            ;;
    esac
}

main "$@"
