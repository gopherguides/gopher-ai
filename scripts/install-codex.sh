#!/usr/bin/env bash
# install-codex.sh — Install or update gopher-ai Codex skills
# Usage:
#   bash install-codex.sh --user              # Install to $HOME/.agents/skills/
#   bash install-codex.sh --repo .            # Install to ./.agents/skills/
#   bash install-codex.sh --repo /path/to     # Install to /path/to/.agents/skills/
#   bash install-codex.sh --legacy            # Install to ~/.codex/skills/ (deprecated)
#   bash install-codex.sh                     # Default: --user
#
# This script clones the gopher-ai repo, builds the Codex skill distribution,
# and copies skills to the target location. Existing skills are replaced cleanly.

set -euo pipefail

REPO_URL="https://github.com/gopherguides/gopher-ai"
BRANCH="main"
CLONE_DIR=""

usage() {
    echo "Usage: $0 [--user] [--repo <path>] [--legacy] [--branch <branch>]"
    echo ""
    echo "Install or update gopher-ai skills for OpenAI Codex CLI."
    echo ""
    echo "Options:"
    echo "  --user             Install to \$HOME/.agents/skills/ (default)"
    echo "  --repo <path>      Install to <path>/.agents/skills/ (repo-level)"
    echo "  --legacy           Install to ~/.codex/skills/ (deprecated, use --user)"
    echo "  --branch <name>    Use a specific branch (default: main)"
    echo "  --help             Show this help"
    echo ""
    echo "Skill locations (Codex scans in this order):"
    echo "  Repo-level:   .agents/skills/          Committed to repo, shared with team"
    echo "  User-level:   \$HOME/.agents/skills/    Personal toolkit, all projects"
    echo "  Legacy:       ~/.codex/skills/          Still loaded for backward compat"
    exit 0
}

cleanup() {
    [[ -n "$CLONE_DIR" && -d "$CLONE_DIR" ]] && rm -rf "$CLONE_DIR"
}
trap cleanup EXIT

MODE=""
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)
            MODE="user"
            shift
            ;;
        --repo)
            MODE="repo"
            TARGET="${2:-.}"
            shift 2
            ;;
        --legacy)
            MODE="legacy"
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
    MODE="user"
fi

# ── Determine destination ────────────────────────────────────────────
case "$MODE" in
    user)
        DEST="$HOME/.agents/skills"
        ;;
    repo)
        TARGET=$(cd "$TARGET" && pwd)
        DEST="$TARGET/.agents/skills"
        ;;
    legacy)
        DEST="$HOME/.codex/skills"
        echo "Warning: ~/.codex/skills/ is a legacy path."
        echo "Consider using --user (\$HOME/.agents/skills/) instead."
        echo ""
        ;;
esac

# ── Check for legacy skills and suggest migration ────────────────────
if [[ "$MODE" != "legacy" && -d "$HOME/.codex/skills" ]]; then
    legacy_count=$(find "$HOME/.codex/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$legacy_count" -gt 0 ]]; then
        echo "Note: Found $legacy_count skill(s) at legacy path ~/.codex/skills/"
        echo "After installing to the new location, you can remove the legacy copy:"
        echo "  rm -rf ~/.codex/skills/"
        echo ""
    fi
fi

# ── Clone and build ──────────────────────────────────────────────────
echo "Fetching gopher-ai skills..."
CLONE_DIR=$(mktemp -d)
git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR" 2>/dev/null

if [[ ! -f "$CLONE_DIR/scripts/build-universal.sh" ]]; then
    echo "Error: build script not found in repository"
    exit 1
fi

echo "Building skill distribution..."
(cd "$CLONE_DIR" && bash scripts/build-universal.sh) > /dev/null 2>&1

if [[ ! -d "$CLONE_DIR/dist/codex/skills" ]]; then
    echo "Error: build did not produce Codex skills"
    exit 1
fi

# ── Install skills ───────────────────────────────────────────────────
mkdir -p "$DEST"

installed=0
for skill_dir in "$CLONE_DIR/dist/codex/skills"/*/; do
    if [[ -f "$skill_dir/SKILL.md" ]]; then
        skill_name=$(basename "$skill_dir")
        rm -rf "${DEST:?}/$skill_name"
        cp -r "$skill_dir" "$DEST/$skill_name"
        echo "  Installed: $skill_name"
        installed=$((installed + 1))
    fi
done

echo ""
echo "Done! $installed skills installed to $DEST/"

if [[ "$MODE" == "repo" ]]; then
    echo ""
    echo "Next steps:"
    echo "  1. git add .agents/skills/"
    echo "  2. git commit -m 'feat: add gopher-ai Codex skills'"
fi

echo ""
echo "Skills activate automatically in Codex based on context."
echo "You can also invoke directly: \$go-best-practices, \$second-opinion, etc."
