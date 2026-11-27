#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/dist/agy"
CONFIG_DIR="${AGY_CONFIG_DIR:-$HOME/.gemini/config}"
LEGACY_DIR="$HOME/.gemini/antigravity-cli/plugins"
PLUGIN_ROOT_TOKEN="__GOPHER_AI_AGY_PLUGIN_ROOT__"
ACTION="install"
CLEANUP_LEGACY=true

usage() {
    cat <<'EOF'
Usage:
  scripts/install-agy.sh [--source DIR] [--config-dir DIR] [--no-cleanup-legacy]
  scripts/install-agy.sh --uninstall [--config-dir DIR]

Installs the native gopher-ai Antigravity (agy) plugins built by
scripts/build-universal.sh (dist/agy/plugins/gopher-ai-*) into the global
Antigravity plugin directory (default: ~/.gemini/config/plugins/).

Only gopher-ai-* plugin directories are managed, so other plugins in
~/.gemini/config/plugins/ are untouched. On install, stale legacy imports under
~/.gemini/antigravity-cli/plugins/gopher-ai-* are also cleaned up unless
--no-cleanup-legacy is passed.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --config-dir) CONFIG_DIR="$2"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --no-cleanup-legacy) CLEANUP_LEGACY=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

PLUGINS_DIR="$CONFIG_DIR/plugins"

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

replace_token() {
    local file="$1"
    local value="$2"
    local tmp="$file.gopher-ai-tmp"
    GOPHER_AI_TOKEN="$PLUGIN_ROOT_TOKEN" GOPHER_AI_VALUE="$value" awk '
        BEGIN { token = ENVIRON["GOPHER_AI_TOKEN"]; value = ENVIRON["GOPHER_AI_VALUE"] }
        {
            line = $0
            out = ""
            while ((i = index(line, token)) > 0) {
                out = out substr(line, 1, i - 1) value
                line = substr(line, i + length(token))
            }
            print out line
        }
    ' "$file" > "$tmp"
    chmod "$(file_mode "$file")" "$tmp"
    mv "$tmp" "$file"
}

cleanup_legacy_plugins() {
    $CLEANUP_LEGACY || return 0
    [[ -d "$LEGACY_DIR" ]] || return 0
    local removed=0
    local legacy_plugin
    for legacy_plugin in "$LEGACY_DIR"/gopher-ai-*; do
        [[ -d "$legacy_plugin" ]] || continue
        rm -rf "$legacy_plugin"
        removed=$((removed + 1))
    done
    if [[ $removed -gt 0 ]]; then
        echo "  Cleaned up $removed legacy plugin(s) from $LEGACY_DIR."
    fi
}

uninstall() {
    if [[ ! -d "$PLUGINS_DIR" ]]; then
        echo "  No gopher-ai Antigravity plugins found in $PLUGINS_DIR."
        return 0
    fi
    local removed=0
    local plugin_dir
    for plugin_dir in "$PLUGINS_DIR"/gopher-ai-*; do
        [[ -d "$plugin_dir" ]] || continue
        rm -rf "$plugin_dir"
        removed=$((removed + 1))
    done
    if [[ $removed -eq 0 ]]; then
        echo "  No gopher-ai Antigravity plugins found in $PLUGINS_DIR."
    else
        echo "  Removed $removed gopher-ai plugin(s) from $PLUGINS_DIR."
    fi
}

install() {
    if [[ ! -d "$SOURCE_DIR/plugins" ]]; then
        echo "error: Antigravity bundle not found at $SOURCE_DIR; run scripts/build-universal.sh first" >&2
        exit 1
    fi

    mkdir -p "$PLUGINS_DIR"
    local plugins_abs
    plugins_abs="$(cd "$PLUGINS_DIR" && pwd -P)"

    local installed=0
    local src_plugin
    for src_plugin in "$SOURCE_DIR"/plugins/gopher-ai-*; do
        [[ -d "$src_plugin" ]] || continue
        local plugin_name
        plugin_name="$(basename "$src_plugin")"
        local dest="$plugins_abs/$plugin_name"
        local stage
        stage="$(mktemp -d "$plugins_abs/.${plugin_name}.stage.XXXXXX")"

        cp -R "$src_plugin/." "$stage/"

        local file
        while IFS= read -r file; do
            [[ -n "$file" ]] && replace_token "$file" "$dest"
        done < <(grep -rlF -- "$PLUGIN_ROOT_TOKEN" "$stage" || true)

        local previous=""
        if [[ -e "$dest" ]]; then
            previous="$plugins_abs/.${plugin_name}.prev.$$"
            mv "$dest" "$previous"
        fi
        mv "$stage" "$dest"
        [[ -z "$previous" ]] || rm -rf "$previous"
        installed=$((installed + 1))
    done

    if [[ $installed -eq 0 ]]; then
        echo "error: no gopher-ai-* plugins found in $SOURCE_DIR/plugins" >&2
        exit 1
    fi

    local version="unknown"
    if [[ -f "$SOURCE_DIR/VERSION" ]]; then
        version="$(cat "$SOURCE_DIR/VERSION")"
    fi
    echo "  Installed $installed gopher-ai plugin(s) (v$version) for Antigravity in $plugins_abs."
    cleanup_legacy_plugins
}

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall
else
    install
fi
