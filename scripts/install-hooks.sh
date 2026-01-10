#!/bin/bash
# Install git hooks for this repository
#
# Run this after cloning the repo to enable automatic shared file syncing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
GITHOOKS_DIR="$ROOT_DIR/githooks"

echo "Installing git hooks..."

# Ensure .git/hooks exists
mkdir -p "$HOOKS_DIR"

# Create symlink to tracked pre-commit hook
if [ -L "$HOOKS_DIR/pre-commit" ]; then
  rm "$HOOKS_DIR/pre-commit"
elif [ -f "$HOOKS_DIR/pre-commit" ]; then
  echo "Backing up existing pre-commit hook to pre-commit.bak"
  mv "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-commit.bak"
fi

ln -s "../../githooks/pre-commit" "$HOOKS_DIR/pre-commit"
chmod +x "$GITHOOKS_DIR/pre-commit"

echo "Git hooks installed successfully!"
echo ""
echo "The pre-commit hook will:"
echo "  1. Automatically sync shared/ changes to plugins"
echo "  2. Stage the synced files"
echo "  3. Verify all files are in sync before commit"
echo ""
echo "To uninstall: rm .git/hooks/pre-commit"
