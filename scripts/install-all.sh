#!/bin/bash
# install-all.sh — Single command to build and install gopher-ai for all detected platforms.
#
# Usage:
#   ./scripts/install-all.sh           # Auto-detect and install for all available platforms
#   ./scripts/install-all.sh --force   # Skip confirmation prompt
#
# Platforms detected:
#   - Claude Code: updates marketplace repo + plugin cache (requires ~/.claude/)
#   - Codex CLI:   installs plugins globally to ~/.codex/plugins/ (so they
#                  load in every Codex session) AND cleans up legacy
#                  ~/.codex/skills/ entries from older flat-install attempts.
#   - Gemini CLI:  installs extensions (requires gemini command)
#
# Remote install (no clone needed — downloads to tmp, installs, cleans up):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
set -euo pipefail

# Resolve script location. When run via curl pipe or process substitution,
# BASH_SOURCE[0] won't point to a real file — that's fine, bootstrap_if_needed
# handles it by downloading the repo to a temp directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "/tmp")"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "/tmp")"
DIST_DIR="$ROOT_DIR/dist"
REPO_SLUG="${GOPHER_AI_REPO:-gopherguides/gopher-ai}"
REPO_REF="${GOPHER_AI_REF:-main}"
ARCHIVE_URL="${GOPHER_AI_ARCHIVE_URL:-https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}}"
BOOTSTRAP_DIR=""
BOOTSTRAPPED=false
FORCE=false

# Auto-force when stdin is not a terminal (curl pipe, CI, etc.)
if [[ ! -t 0 ]]; then
    FORCE=true
fi

cleanup() {
    if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_DIR"
    fi
}
trap cleanup EXIT

# If we're running from a curl pipe (no local repo), bootstrap from GitHub.
# Prefers `git clone` so the Codex cleanup migration has full history access;
# falls back to `curl | tar` if git is missing (the shipped legacy-skill-hashes
# manifest covers ownership verification in that case).
#
# When the caller explicitly sets GOPHER_AI_ARCHIVE_URL (e.g., to test a PR
# tarball, commit archive, or local mirror), we honor it — clone is only
# preferred for the default GitHub source.
bootstrap_if_needed() {
    if [[ -f "$ROOT_DIR/scripts/build-universal.sh" ]]; then
        return
    fi

    echo "No local repo detected — bootstrapping from GitHub..."
    BOOTSTRAP_DIR="$(mktemp -d)"
    local extracted=""

    if [[ -z "${GOPHER_AI_ARCHIVE_URL:-}" ]] && command -v git >/dev/null 2>&1; then
        local clone_url="https://github.com/${REPO_SLUG}.git"
        extracted="$BOOTSTRAP_DIR/gopher-ai"
        echo "Bootstrap source: git clone $clone_url@$REPO_REF"
        if ! git clone --quiet --branch "$REPO_REF" --single-branch \
                "$clone_url" "$extracted" 2>/dev/null; then
            # Remove the partial clone so the tar fallback's `find` doesn't pick
            # this broken directory over the freshly-extracted archive.
            rm -rf "$extracted"
            extracted=""
        fi
    fi

    if [[ -z "$extracted" ]]; then
        command -v curl >/dev/null 2>&1 || { echo "error: curl required for remote install" >&2; exit 1; }
        command -v tar >/dev/null 2>&1 || { echo "error: tar required for remote install" >&2; exit 1; }
        echo "Bootstrap source: curl $ARCHIVE_URL"
        curl -fsSL "$ARCHIVE_URL" | tar -xz -C "$BOOTSTRAP_DIR"
        extracted="$(find "$BOOTSTRAP_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    fi

    if [[ -z "$extracted" || ! -f "$extracted/scripts/build-universal.sh" ]]; then
        echo "error: failed to bootstrap gopher-ai from $REPO_SLUG@$REPO_REF" >&2
        exit 1
    fi

    ROOT_DIR="$extracted"
    SCRIPT_DIR="$ROOT_DIR/scripts"
    DIST_DIR="$ROOT_DIR/dist"
    BOOTSTRAPPED=true
    echo "Bootstrapped from: $REPO_SLUG@$REPO_REF"
    echo ""
}

# Check that the tools required for the platforms we're actually installing
# are available.
check_prerequisites() {
    local missing=()

    # jq is needed by build-universal.sh (Claude/Gemini) and by install-codex.sh
    # for marketplace.json manipulation when installing globally.
    if $HAVE_CLAUDE || $HAVE_GEMINI || $HAVE_CODEX; then
        if ! command -v jq >/dev/null 2>&1; then
            missing+=("jq (brew install jq / apt install jq)")
        fi
    fi

    # git is needed for Claude marketplace updates.
    if $HAVE_CLAUDE; then
        if ! command -v git >/dev/null 2>&1; then
            missing+=("git")
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "error: missing required tools:" >&2
        for tool in "${missing[@]}"; do
            echo "  - $tool" >&2
        done
        exit 1
    fi
}

# Detect which platforms are available
detect_platforms() {
    HAVE_CLAUDE=false
    HAVE_CODEX=false
    HAVE_GEMINI=false

    if [[ -d "$HOME/.claude" ]]; then
        HAVE_CLAUDE=true
    fi

    # Codex --cleanup doesn't require jq; treat ~/.codex/ as the signal so
    # the migration runs even on minimal machines. (--repo would require jq,
    # but install-all.sh only invokes --cleanup.)
    if [[ -d "$HOME/.codex" ]]; then
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
        echo "  Codex CLI ...... found (~/.codex/ exists — will install global plugins)"
    else
        echo "  Codex CLI ...... skipped (no ~/.codex/ directory)"
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
    echo "  Installing gopher-ai plugins globally to ~/.codex/plugins/."
    echo "  They will load in every Codex session, regardless of working directory."
    echo ""
    "$ROOT_DIR/scripts/install-codex.sh" --user
    echo ""
}

install_gemini() {
    echo "=== Gemini CLI ==="

    # Gemini extensions reference their source path after install.
    # When bootstrapped from a curl pipe, the source is a temp dir that gets
    # cleaned up on exit. Stage extensions to a permanent location first.
    local gemini_src="$DIST_DIR/gemini"
    if $BOOTSTRAPPED; then
        local permanent_dir="$HOME/.local/share/gopher-ai/gemini"
        echo "  Staging extensions to $permanent_dir (persistent across updates)..."
        rm -rf "$permanent_dir"
        mkdir -p "$permanent_dir"
        cp -R "$gemini_src"/gopher-ai-* "$permanent_dir/" 2>/dev/null || true
        gemini_src="$permanent_dir"
    fi

    local installed=0
    local failed=0
    local out_file err_file
    out_file="$(mktemp)"
    err_file="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$out_file' '$err_file'" RETURN

    for ext_dir in "$gemini_src"/gopher-ai-*/; do
        [[ -d "$ext_dir" ]] || continue
        local ext_name
        ext_name="$(basename "$ext_dir")"

        # `gemini extensions install` refuses to run when an extension of the
        # same name is already installed. Uninstall first so updates work.
        # The uninstall failing (e.g. extension wasn't installed before) is fine.
        gemini extensions uninstall "$ext_name" >/dev/null 2>&1 || true

        echo "  Installing extension: $ext_name"
        # --consent skips the interactive trust prompt per extension. Capture
        # per-extension stdout/stderr to mktemp files so unrelated agent-load
        # errors (Gemini eagerly loads every installed extension on each install
        # command) don't flood the log unless this install actually fails.
        if gemini extensions install "$ext_dir" --consent >"$out_file" 2>"$err_file"; then
            installed=$((installed + 1))
        else
            echo "  Warning: failed to install $ext_name"
            echo "  --- gemini stderr ---"
            tail -5 "$err_file"
            echo "  ---------------------"
            failed=$((failed + 1))
        fi
    done

    if [[ $installed -gt 0 ]]; then
        echo "  Installed $installed extension(s)."
    fi
    if [[ $failed -gt 0 ]]; then
        echo ""
        echo "  $failed extension(s) failed. Gemini CLI extensions API may have changed."
        echo "  Try manually: gemini extensions install $gemini_src/gopher-ai-<module> --consent"
    fi
    if [[ $installed -eq 0 && $failed -eq 0 ]]; then
        echo "  No extensions found to install."
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
    check_prerequisites

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

    # Build is needed for Claude and Gemini. Codex --user copies straight from
    # plugins/ source — no build artifacts required.
    if $HAVE_CLAUDE || $HAVE_GEMINI; then
        echo "Building distribution..."
        echo ""
        if ! "$ROOT_DIR/scripts/build-universal.sh"; then
            echo ""
            echo "error: build failed." >&2
            echo "Common fixes:" >&2
            echo "  - Install jq: brew install jq (macOS) / sudo apt install jq (Linux)" >&2
            echo "  - Ensure git is installed and available" >&2
            exit 1
        fi
        echo ""
    fi

    $HAVE_CLAUDE && install_claude
    $HAVE_CODEX && install_codex
    $HAVE_GEMINI && install_gemini

    echo "================================"
    echo "Done! Installed for: ${platforms[*]}"
    echo ""
    echo "Next steps:"
    if $HAVE_CLAUDE; then
        echo "  Claude Code: Restart Claude Code to reload plugins"
    fi
    if $HAVE_CODEX; then
        echo "  Codex CLI:   Plugins installed to ~/.codex/plugins/ — restart Codex to load."
    fi
    if $HAVE_GEMINI; then
        echo "  Gemini CLI:  Restart Gemini to load extensions"
    fi
}

main "$@"
