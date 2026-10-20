#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/dist/opencode"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
HOME_TOKEN="__GOPHER_AI_OPENCODE_HOME__"
ACTION="install"
RELOAD=true

usage() {
    cat <<'EOF'
Usage:
  scripts/install-opencode.sh [--source DIR] [--config-dir DIR] [--no-reload]
  scripts/install-opencode.sh --uninstall [--config-dir DIR] [--no-reload]

Installs the gopher-ai OpenCode bundle built by scripts/build-universal.sh
(dist/opencode) into the OpenCode global configuration directory
(default: ${XDG_CONFIG_HOME:-~/.config}/opencode):

  skills/gopher-ai/<plugin>/<skill>/   skills, loaded by id (for example `go`)
  commands/<plugin>/<command>.md       commands, run as /<plugin>/<command>
  agents/<plugin>/<agent>.md           subagents, named <plugin>/<agent>
  gopher-ai/                           plugin runtime files and install manifest

Only files recorded in gopher-ai/manifest.txt are replaced or removed, so
existing user files are never overwritten. Safe to run while OpenCode is
running; a running background service is told to reload its configuration.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_DIR="$2"; shift 2 ;;
        --config-dir) CONFIG_DIR="$2"; shift 2 ;;
        --uninstall) ACTION="uninstall"; shift ;;
        --no-reload) RELOAD=false; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

OWNED_DIR="$CONFIG_DIR/gopher-ai"
MANIFEST="$OWNED_DIR/manifest.txt"

read_manifest() {
    if [[ -f "$MANIFEST" ]]; then
        grep -E '^(skills|commands|agents)/' "$MANIFEST" | grep -vE '(^|/)\.\.(/|$)' || true
    fi
}

in_list() {
    local needle="$1"
    local list="$2"
    [[ -n "$list" ]] && grep -Fxq -- "$needle" <<< "$list"
}

file_mode() {
    if stat -c '%a' "$1" >/dev/null 2>&1; then
        stat -c '%a' "$1"
    else
        stat -f '%Lp' "$1"
    fi
}

replace_token() {
    local file="$1"
    local tmp="$file.gopher-ai-tmp"
    GOPHER_AI_TOKEN="$HOME_TOKEN" GOPHER_AI_VALUE="$2" awk '
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

prune_empty_dirs() {
    local top
    for top in skills/gopher-ai commands agents; do
        [[ -d "$CONFIG_DIR/$top" ]] || continue
        find "$CONFIG_DIR/$top" -mindepth 1 -depth -type d -empty -exec rmdir {} + 2>/dev/null || true
    done
    rmdir "$CONFIG_DIR/skills/gopher-ai" 2>/dev/null || true
}

remove_owned_files() {
    local keep="$1"
    local rel
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if in_list "$rel" "$keep"; then
            continue
        fi
        rm -f "$CONFIG_DIR/$rel"
    done < <(read_manifest)
}

reload_service() {
    $RELOAD || return 0
    command -v opencode >/dev/null 2>&1 || return 0
    if opencode service status >/dev/null 2>&1; then
        if opencode reload >/dev/null 2>&1; then
            echo "  Reloaded the running OpenCode service."
        else
            echo "  Warning: could not reload the OpenCode service; run: opencode reload"
        fi
    fi
}

uninstall() {
    if [[ ! -f "$MANIFEST" ]]; then
        echo "  No gopher-ai OpenCode install found in $CONFIG_DIR."
        return 0
    fi
    remove_owned_files ""
    rm -rf "$OWNED_DIR"
    prune_empty_dirs
    echo "  Removed gopher-ai from $CONFIG_DIR."
    reload_service
}

install() {
    if [[ ! -d "$SOURCE_DIR/gopher-ai/plugins" ]]; then
        echo "error: OpenCode bundle not found at $SOURCE_DIR; run scripts/build-universal.sh first" >&2
        exit 1
    fi

    if [[ -e "$OWNED_DIR" && ! -f "$MANIFEST" ]]; then
        echo "error: $OWNED_DIR exists but was not created by this installer (no manifest.txt); move it aside and rerun" >&2
        exit 1
    fi

    mkdir -p "$CONFIG_DIR"
    local config_abs
    config_abs="$(cd "$CONFIG_DIR" && pwd -P)"
    local stage
    stage="$(mktemp -d "$config_abs/.gopher-ai-stage.XXXXXX")"
    trap 'rm -rf "$stage"' EXIT

    cp -R "$SOURCE_DIR/." "$stage/"
    local owned_abs="$config_abs/gopher-ai"
    local file
    while IFS= read -r file; do
        [[ -n "$file" ]] && replace_token "$file" "$owned_abs"
    done < <(grep -rlF -- "$HOME_TOKEN" "$stage" || true)

    local new_files
    new_files=$(cd "$stage" && find skills commands agents -type f 2>/dev/null | LC_ALL=C sort)
    local previous
    previous=$(read_manifest)

    local installed=""
    local skipped=0
    local rel
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if [[ -e "$config_abs/$rel" || -L "$config_abs/$rel" ]] && ! in_list "$rel" "$previous"; then
            echo "  Skipping $rel: a file not installed by gopher-ai already exists there."
            skipped=$((skipped + 1))
            continue
        fi
        mkdir -p "$(dirname "$config_abs/$rel")"
        rm -f "$config_abs/$rel"
        cp -p "$stage/$rel" "$config_abs/$rel"
        installed+="$rel"$'\n'
    done <<< "$new_files"

    remove_owned_files "$installed"

    rm -rf "$stage/skills" "$stage/commands" "$stage/agents"
    printf '%s' "$installed" > "$stage/gopher-ai/manifest.txt"
    local previous_owned=""
    if [[ -e "$owned_abs" ]]; then
        previous_owned="$config_abs/.gopher-ai-previous.$$"
        mv "$owned_abs" "$previous_owned"
    fi
    mv "$stage/gopher-ai" "$owned_abs"
    [[ -z "$previous_owned" ]] || rm -rf "$previous_owned"
    rm -rf "$stage"
    trap - EXIT

    prune_empty_dirs

    local count
    count=$(printf '%s' "$installed" | grep -c . || true)
    echo "  Installed gopher-ai $(cat "$owned_abs/VERSION") for OpenCode: $count files in $config_abs."
    if [[ $skipped -gt 0 ]]; then
        echo "  Warning: skipped $skipped file(s) that already existed and are not owned by gopher-ai."
    fi
    reload_service
}

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall
else
    install
fi
