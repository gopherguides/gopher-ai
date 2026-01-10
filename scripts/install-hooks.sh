#!/bin/bash
# Install git hooks for this repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"

echo "Installing git hooks..."

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'EOF'
#!/bin/bash
# Pre-commit hook: sync shared files and stage them

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Check if any shared files were modified
SHARED_CHANGED=$(git diff --cached --name-only | grep -E "^shared/" || true)

if [ -n "$SHARED_CHANGED" ]; then
  echo "Shared files changed, running sync..."
  "$ROOT_DIR/scripts/sync-shared.sh"

  # Stage the synced files
  git add \
    plugins/go-workflow/hooks \
    plugins/go-workflow/scripts \
    plugins/go-workflow/lib \
    plugins/go-workflow/commands/cancel-loop.md \
    plugins/go-web/hooks \
    plugins/go-web/scripts \
    plugins/go-web/lib \
    plugins/go-web/commands/cancel-loop.md \
    plugins/go-dev/hooks \
    plugins/go-dev/scripts \
    plugins/go-dev/lib \
    plugins/go-dev/commands/cancel-loop.md \
    plugins/tailwind/hooks \
    plugins/tailwind/scripts \
    plugins/tailwind/lib \
    plugins/tailwind/commands/cancel-loop.md \
    2>/dev/null || true

  echo "Synced files staged for commit."
fi

# Verify sync is correct
"$ROOT_DIR/scripts/check-shared-sync.sh"
EOF

chmod +x "$HOOKS_DIR/pre-commit"

echo "Git hooks installed successfully!"
echo ""
echo "The pre-commit hook will:"
echo "  1. Automatically sync shared/ changes to plugins"
echo "  2. Stage the synced files"
echo "  3. Verify all files are in sync"
