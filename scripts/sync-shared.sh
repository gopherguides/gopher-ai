#!/bin/bash
# Sync shared files to all plugins that use loop functionality
# Run this after modifying anything in shared/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SHARED_DIR="$ROOT_DIR/shared"
PLUGINS_DIR="$ROOT_DIR/plugins"

# Plugins that use the shared loop infrastructure
LOOP_PLUGINS=("go-workflow" "go-web" "go-dev" "tailwind")

echo "Syncing shared files to plugins..."

for plugin in "${LOOP_PLUGINS[@]}"; do
  PLUGIN_DIR="$PLUGINS_DIR/$plugin"

  if [ ! -d "$PLUGIN_DIR" ]; then
    echo "Warning: Plugin directory not found: $PLUGIN_DIR"
    continue
  fi

  echo "  Syncing to $plugin..."

  # Remove old symlinks if they exist
  for item in hooks scripts; do
    if [ -L "$PLUGIN_DIR/$item" ]; then
      rm "$PLUGIN_DIR/$item"
    fi
  done
  if [ -L "$PLUGIN_DIR/commands/cancel-loop.md" ]; then
    rm "$PLUGIN_DIR/commands/cancel-loop.md"
  fi

  # Create directories if they don't exist
  mkdir -p "$PLUGIN_DIR/hooks"
  mkdir -p "$PLUGIN_DIR/scripts"
  mkdir -p "$PLUGIN_DIR/lib"

  # Copy hooks
  cp "$SHARED_DIR/hooks/"* "$PLUGIN_DIR/hooks/"

  # Copy scripts
  cp "$SHARED_DIR/scripts/"* "$PLUGIN_DIR/scripts/"

  # Copy lib
  cp "$SHARED_DIR/lib/"* "$PLUGIN_DIR/lib/"

  # Copy cancel-loop command
  cp "$SHARED_DIR/commands/cancel-loop.md" "$PLUGIN_DIR/commands/cancel-loop.md"

  # Ensure scripts are executable
  chmod +x "$PLUGIN_DIR/hooks/"*.sh 2>/dev/null || true
  chmod +x "$PLUGIN_DIR/scripts/"*.sh 2>/dev/null || true
  chmod +x "$PLUGIN_DIR/lib/"*.sh 2>/dev/null || true
done

echo "Sync complete!"
echo ""
echo "Files synced from shared/ to plugins:"
echo "  - hooks/stop-hook.sh"
echo "  - scripts/setup-loop.sh"
echo "  - scripts/cleanup-loop.sh"
echo "  - lib/loop-state.sh"
echo "  - commands/cancel-loop.md"
