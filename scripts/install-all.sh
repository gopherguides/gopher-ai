#!/bin/bash
# install-all.sh — Single command to build and install gopher-ai for all detected platforms.
#
# Usage:
#   ./scripts/install-all.sh           # Auto-detect and install for all available platforms
#   ./scripts/install-all.sh --force   # Skip confirmation prompt
#
# Platforms detected:
#   - Claude Code: updates marketplace repo + plugin cache (requires ~/.claude/)
#   - Codex CLI:   installs flat skills to ~/.codex/skills/ (requires jq)
#   - Gemini CLI:  installs extensions (requires gemini command)
#
# One-liner from GitHub:
#   bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
REPO_SLUG="${GOPHER_AI_REPO:-gopherguides/gopher-ai}"
REPO_REF="${GOPHER_AI_REF:-main}"
ARCHIVE_URL="${GOPHER_AI_ARCHIVE_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}}"
BOOTSTRAP_DIR=""
FORCE=false

cleanup() {
    if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_DIR"
    fi
}
trap cleanup EXIT

# If we're running from a curl pipe (no local repo), bootstrap from GitHub
bootstrap_if_needed() {
    if [[ -f "$ROOT_DIR/scripts/build-universal.sh" ]]; then
        return
    fi

    echo "No local repo detected — bootstrapping from GitHub..."
    command -v curl >/dev/null 2>&1 || { echo "error: curl required for remote install" >&2; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo "error: tar required for remote install" >&2; exit 1; }

    BOOTSTRAP_DIR="$(mktemp -d)"
    curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$BOOTSTRAP_DIR"

    local extracted
    extracted="$(find "$BOOTSTRAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [[ -z "$extracted" || ! -f "$extracted/scripts/build-universal.sh" ]]; then
        echo "error: failed to bootstrap gopher-ai from $ARCHIVE_URL" >&2
        exit 1
    fi

    ROOT_DIR="$extracted"
    SCRIPT_DIR="$ROOT_DIR/scripts"
    DIST_DIR="$ROOT_DIR/dist"
    echo "Bootstrapped from: $REPO_SLUG@$REPO_REF"
    echo ""
}

# Detect which platforms are available
detect_platforms() {
    HAVE_CLAUDE=false
    HAVE_CODEX=false
    HAVE_GEMINI=false

    if [[ -d "$HOME/.claude" ]]; then
        HAVE_CLAUDE=true
    fi

    if command -v jq >/dev/null 2>&1; then
        HAVE_CODEX=true
    fi

    if command -v gemini >/dev/null 2>&1; then
        HAVE_GEMINI=true
    fi
}

print_detection() {
    echo "Platform detection:"
    if $HAVE_CLAUDE; then
        echo "  Claude Code .... found (~/.claude/ exists)"
    else
        echo "  Claude Code .... not found (no ~/.claude/ directory)"
    fi

    if $HAVE_CODEX; then
        echo "  Codex CLI ...... found (jq available for install)"
    else
        echo "  Codex CLI ...... skipped (jq not found — install with: brew install jq)"
    fi

    if $HAVE_GEMINI; then
        echo "  Gemini CLI ..... found ($(command -v gemini))"
    else
        echo "  Gemini CLI ..... not found (install with: npm install -g @google/gemini-cli)"
    fi
    echo ""
}

install_claude() {
    echo "=== Claude Code ==="
    local marketplace_dir="$HOME/.claude/plugins/marketplaces/gopher-ai"

    if [[ -d "$marketplace_dir" ]]; then
        echo "  Updating marketplace repo..."
        git -C "$marketplace_dir" fetch origin 2>/dev/null
        git -C "$marketplace_dir" reset --hard origin/main 2>/dev/null
        echo "  Running refresh..."
        "$ROOT_DIR/scripts/refresh-plugins.sh"
    else
        echo "  Marketplace not yet added."
        echo "  Run this inside Claude Code first:"
        echo "    /plugin marketplace add gopherguides/gopher-ai"
        echo ""
        echo "  Then re-run this script to complete the install."
    fi
    echo ""
}

install_codex() {
    echo "=== Codex CLI ==="

    # Build if not already built
    if [[ ! -f "$DIST_DIR/codex/plugins/marketplace.json" ]]; then
        echo "  Building distribution..."
        "$ROOT_DIR/scripts/build-universal.sh" >/dev/null 2>&1
    fi

    "$ROOT_DIR/scripts/install-codex.sh" --user
    echo ""
}

install_gemini() {
    echo "=== Gemini CLI ==="

    # Build if not already built
    if [[ ! -d "$DIST_DIR/gemini" ]]; then
        echo "  Building distribution..."
        "$ROOT_DIR/scripts/build-universal.sh" >/dev/null 2>&1
    fi

    local installed=0
    for ext_dir in "$DIST_DIR"/gemini/gopher-ai-*/; do
        [[ -d "$ext_dir" ]] || continue
        local ext_name
        ext_name="$(basename "$ext_dir")"
        echo "  Installing extension: $ext_name"
        gemini extensions install "$ext_dir" 2>/dev/null || {
            echo "  Warning: failed to install $ext_name (gemini extensions install may not be supported yet)"
            continue
        }
        installed=$((installed + 1))
    done

    if [[ $installed -eq 0 ]]; then
        echo "  No extensions installed. You can install manually:"
        echo "    gemini extensions install ./dist/gemini/gopher-ai-<module>"
    fi
    echo ""
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --force|-f) FORCE=true ;;
            --help|-h)
                echo "Usage: ./scripts/install-all.sh [--force]"
                echo ""
                echo "Build and install gopher-ai for all detected platforms."
                echo "Detects Claude Code, Codex CLI, and Gemini CLI automatically."
                echo ""
                echo "Options:"
                echo "  --force, -f   Skip confirmation prompt"
                echo "  --help, -h    Show this help"
                exit 0
                ;;
        esac
    done

    echo ""
    echo "gopher-ai — universal installer"
    echo "================================"
    echo ""

    bootstrap_if_needed
    detect_platforms

    if ! $HAVE_CLAUDE && ! $HAVE_CODEX && ! $HAVE_GEMINI; then
        echo "No supported platforms detected."
        echo ""
        echo "Install at least one:"
        echo "  Claude Code: https://claude.ai/code"
        echo "  Codex CLI:   npm install -g @openai/codex"
        echo "  Gemini CLI:  npm install -g @google/gemini-cli"
        exit 1
    fi

    print_detection

    # Count platforms to install
    local platforms=()
    $HAVE_CLAUDE && platforms+=("Claude Code")
    $HAVE_CODEX && platforms+=("Codex CLI")
    $HAVE_GEMINI && platforms+=("Gemini CLI")

    if ! $FORCE; then
        echo "Will install for: ${platforms[*]}"
        read -rp "Continue? [Y/n] " answer
        case "${answer:-y}" in
            [Yy]*|"") ;;
            *) echo "Aborted."; exit 0 ;;
        esac
        echo ""
    fi

    # Build once, install everywhere
    echo "Building distribution..."
    "$ROOT_DIR/scripts/build-universal.sh" >/dev/null 2>&1
    echo "Build complete."
    echo ""

    $HAVE_CLAUDE && install_claude
    $HAVE_CODEX && install_codex
    $HAVE_GEMINI && install_gemini

    echo "================================"
    echo "Done! Installed for: ${platforms[*]}"
    echo ""
    echo "Next steps:"
    $HAVE_CLAUDE && echo "  Claude Code: Restart Claude Code to reload plugins"
    $HAVE_CODEX && echo "  Codex CLI:   Restart Codex — use /plugins to verify"
    $HAVE_GEMINI && echo "  Gemini CLI:  Restart Gemini to load extensions"
}

main "$@"
