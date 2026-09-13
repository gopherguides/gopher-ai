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
LOOP_PLUGINS=("go-workflow" "go-web" "go-dev" "tailwind" "llm-tools")

# Only go-workflow has the stop hook
HOOK_PLUGIN="go-workflow"

# Files synced to all plugins
COMMON_FILES=(
  "scripts/screenshot-evidence.py"
  "lib/screenshot-evidence.md"
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

LEGACY_MANIFEST="$ROOT_DIR/scripts/legacy-skill-hashes.txt"
LEGACY_HOOK_MANIFEST="$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt"

if [ ! -f "$LEGACY_MANIFEST" ] || [ ! -f "$LEGACY_HOOK_MANIFEST" ]; then
  echo "ERROR: legacy skill hash manifest is missing"
  OUT_OF_SYNC=1
elif ! cmp -s "$LEGACY_MANIFEST" "$LEGACY_HOOK_MANIFEST"; then
  echo "ERROR: legacy skill hash manifests differ"
  OUT_OF_SYNC=1
else
  for skill_file in "$PLUGINS_DIR"/*/skills/*/SKILL.md; do
    [ -f "$skill_file" ] || continue
    skill_name="$(basename "$(dirname "$skill_file")")"
    skill_hash="$(sha256sum "$skill_file" | awk '{print $1}')"
    pair="$skill_hash $skill_name"
    if ! awk -v pair="$pair" '$0 == pair { found = 1 } END { exit found ? 0 : 1 }' "$LEGACY_MANIFEST"; then
      echo "ERROR: legacy skill hash manifest missing current skill hash: $pair"
      OUT_OF_SYNC=1
    fi
  done
fi

if [ $OUT_OF_SYNC -eq 1 ]; then
  echo ""
  echo "Files are out of sync! Run the applicable sync or legacy hash regeneration script."
  exit 1
else
  echo "All shared files are in sync."
  exit 0
fi
