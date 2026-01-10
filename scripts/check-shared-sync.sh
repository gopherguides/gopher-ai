#!/bin/bash
# Check that shared files are in sync with all plugins
# Used by CI to verify sync was run before commit
#
# Note: Only go-workflow has hooks (it owns persistent loop management).
# Other plugins get scripts, lib, and commands for loop support.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SHARED_DIR="$ROOT_DIR/shared"
PLUGINS_DIR="$ROOT_DIR/plugins"

# Plugins that use the shared loop infrastructure
LOOP_PLUGINS=("go-workflow" "go-web" "go-dev" "tailwind")

# Only go-workflow has the stop hook
HOOK_PLUGIN="go-workflow"

# Files synced to all plugins
COMMON_FILES=(
  "scripts/setup-loop.sh"
  "scripts/cleanup-loop.sh"
  "lib/loop-state.sh"
  "commands/cancel-loop.md"
)

# Files only synced to go-workflow
HOOK_FILES=(
  "hooks/stop-hook.sh"
)

OUT_OF_SYNC=0

echo "Checking shared file sync..."

for plugin in "${LOOP_PLUGINS[@]}"; do
  PLUGIN_DIR="$PLUGINS_DIR/$plugin"

  if [ ! -d "$PLUGIN_DIR" ]; then
    echo "Warning: Plugin directory not found: $PLUGIN_DIR"
    continue
  fi

  # Check common files for all plugins
  for file in "${COMMON_FILES[@]}"; do
    SHARED_FILE="$SHARED_DIR/$file"
    PLUGIN_FILE="$PLUGIN_DIR/$file"

    # Check if plugin file exists
    if [ ! -f "$PLUGIN_FILE" ]; then
      if [ -L "$PLUGIN_FILE" ] || [ -L "$(dirname "$PLUGIN_FILE")" ]; then
        echo "ERROR: $plugin/$file is a symlink, should be a copy"
        OUT_OF_SYNC=1
      else
        echo "ERROR: $plugin/$file is missing"
        OUT_OF_SYNC=1
      fi
      continue
    fi

    # Check if it's a symlink (should be a copy now)
    if [ -L "$PLUGIN_FILE" ]; then
      echo "ERROR: $plugin/$file is a symlink, should be a copy"
      OUT_OF_SYNC=1
      continue
    fi

    # Compare files
    if ! diff -q "$SHARED_FILE" "$PLUGIN_FILE" > /dev/null 2>&1; then
      echo "ERROR: $plugin/$file differs from shared/$file"
      OUT_OF_SYNC=1
    fi
  done

  # Check hook files only for go-workflow
  if [ "$plugin" = "$HOOK_PLUGIN" ]; then
    for file in "${HOOK_FILES[@]}"; do
      SHARED_FILE="$SHARED_DIR/$file"
      PLUGIN_FILE="$PLUGIN_DIR/$file"

      if [ ! -f "$PLUGIN_FILE" ]; then
        echo "ERROR: $plugin/$file is missing"
        OUT_OF_SYNC=1
        continue
      fi

      if [ -L "$PLUGIN_FILE" ]; then
        echo "ERROR: $plugin/$file is a symlink, should be a copy"
        OUT_OF_SYNC=1
        continue
      fi

      if ! diff -q "$SHARED_FILE" "$PLUGIN_FILE" > /dev/null 2>&1; then
        echo "ERROR: $plugin/$file differs from shared/$file"
        OUT_OF_SYNC=1
      fi
    done
  fi
done

if [ $OUT_OF_SYNC -eq 1 ]; then
  echo ""
  echo "Files are out of sync! Run: ./scripts/sync-shared.sh"
  exit 1
else
  echo "All shared files are in sync."
  exit 0
fi
