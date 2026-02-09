#!/usr/bin/env bash
# install.sh — Install Gopher AI agent skills
# Usage:
#   bash install.sh --repo .           # Install to current repo
#   bash install.sh --repo /path/to    # Install to specific repo
#   bash install.sh --personal         # Install to ~/.copilot/skills/
#
# Ref: https://github.com/gopherguides/gopher-ai/issues/51

set -euo pipefail

REPO_URL="https://github.com/gopherguides/gopher-ai"
BRANCH="main"
TMPDIR=""

usage() {
    echo "Usage: $0 [--repo <path>] [--personal] [--branch <branch>]"
    echo ""
    echo "Options:"
    echo "  --repo <path>    Install skills to a repository's .github/skills/"
    echo "  --personal       Install to ~/.copilot/skills/ (works across all repos)"
    echo "  --branch <name>  Use a specific branch (default: main)"
    echo "  --help           Show this help"
    exit 0
}

cleanup() {
    [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

MODE=""
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            MODE="repo"
            TARGET="${2:-.}"
            shift 2
            ;;
        --personal)
            MODE="personal"
            shift
            ;;
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "Error: specify --repo <path> or --personal"
    echo ""
    usage
fi

# ── Clone source ──────────────────────────────────────────────────────
echo "📦 Fetching gopher-ai skills..."
TMPDIR=$(mktemp -d)
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$TMPDIR" 2>/dev/null

if [[ ! -d "$TMPDIR/.github/skills" ]]; then
    echo "❌ Skills directory not found in repository"
    exit 1
fi

# ── Install ───────────────────────────────────────────────────────────
if [[ "$MODE" == "repo" ]]; then
    TARGET=$(cd "$TARGET" && pwd)
    DEST="$TARGET/.github/skills"
    mkdir -p "$DEST"

    # Copy skills (not the scripts/config — those go too)
    cp -r "$TMPDIR/.github/skills/"* "$DEST/"

    # Also copy agentic workflows if they exist
    if [[ -d "$TMPDIR/.github/agentic-workflows" ]]; then
        mkdir -p "$TARGET/.github/agentic-workflows"
        cp -r "$TMPDIR/.github/agentic-workflows/"* "$TARGET/.github/agentic-workflows/"
        echo "✅ Agentic workflows installed to $TARGET/.github/agentic-workflows/"
    fi

    echo "✅ Skills installed to $DEST/"
    echo ""
    echo "Next steps:"
    echo "  1. git add .github/skills/ .github/agentic-workflows/"
    echo "  2. git commit -m 'feat: add Gopher AI agent skills'"
    echo "  3. Set API key: export GOPHER_GUIDES_API_KEY=\"your-key\""

elif [[ "$MODE" == "personal" ]]; then
    DEST="$HOME/.copilot/skills"
    mkdir -p "$DEST"

    # Copy each skill folder
    for skill_dir in "$TMPDIR/.github/skills"/*/; do
        if [[ -f "$skill_dir/SKILL.md" ]]; then
            skill_name=$(basename "$skill_dir")
            cp -r "$skill_dir" "$DEST/$skill_name"
            echo "  ✅ Installed: $skill_name"
        fi
    done

    echo ""
    echo "✅ Skills installed to $DEST/"
    echo ""
    echo "Next steps:"
    echo "  1. Set API key: export GOPHER_GUIDES_API_KEY=\"your-key\""
    echo "  2. Skills will activate automatically in Copilot Chat"
fi
