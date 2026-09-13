#!/bin/bash
# Check that shared files are in sync with all plugins
# Used by CI to verify sync was run before commit
#
# Note: Only go-workflow has hooks (it owns persistent loop management).
# Other plugins get scripts, lib, and commands for loop support.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

USE_INDEX=false
if [ "${1:-}" = "--cached" ]; then
  USE_INDEX=true
elif [ "$#" -ne 0 ]; then
  echo "Usage: $0 [--cached]" >&2
  exit 2
fi

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

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_index_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    git -C "$ROOT_DIR" show ":$1" | sha256sum | awk '{print $1}'
  else
    git -C "$ROOT_DIR" show ":$1" | shasum -a 256 | awk '{print $1}'
  fi
}

index_file_exists() {
  git -C "$ROOT_DIR" cat-file -e ":$1" 2>/dev/null
}

index_file_is_symlink() {
  [ "$(git -C "$ROOT_DIR" ls-files -s -- "$1" | awk '{print $1}')" = "120000" ]
}

index_files_equal() {
  [ "$(git -C "$ROOT_DIR" ls-files -s -- "$1" | awk '{print $1 " " $2}')" = \
    "$(git -C "$ROOT_DIR" ls-files -s -- "$2" | awk '{print $1 " " $2}')" ]
}

echo "Checking shared file sync..."

for plugin in "${LOOP_PLUGINS[@]}"; do
  PLUGIN_DIR="$PLUGINS_DIR/$plugin"

  if [ "$USE_INDEX" = false ] && [ ! -d "$PLUGIN_DIR" ]; then
    echo "Warning: Plugin directory not found: $PLUGIN_DIR"
    continue
  fi

  # Check common files for all plugins
  for file in "${COMMON_FILES[@]}"; do
    SHARED_FILE="$SHARED_DIR/$file"
    PLUGIN_FILE="$PLUGIN_DIR/$file"

    if [ "$USE_INDEX" = true ]; then
      SHARED_INDEX_FILE="shared/$file"
      PLUGIN_INDEX_FILE="plugins/$plugin/$file"
      if ! index_file_exists "$PLUGIN_INDEX_FILE"; then
        echo "ERROR: $plugin/$file is missing from the index"
        OUT_OF_SYNC=1
      elif index_file_is_symlink "$PLUGIN_INDEX_FILE"; then
        echo "ERROR: $plugin/$file is a symlink in the index, should be a copy"
        OUT_OF_SYNC=1
      elif ! index_file_exists "$SHARED_INDEX_FILE" || ! index_files_equal "$SHARED_INDEX_FILE" "$PLUGIN_INDEX_FILE"; then
        echo "ERROR: $plugin/$file differs from shared/$file in the index"
        OUT_OF_SYNC=1
      fi
      continue
    fi

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

      if [ "$USE_INDEX" = true ]; then
        SHARED_INDEX_FILE="shared/$file"
        PLUGIN_INDEX_FILE="plugins/$plugin/$file"
        if ! index_file_exists "$PLUGIN_INDEX_FILE"; then
          echo "ERROR: $plugin/$file is missing from the index"
          OUT_OF_SYNC=1
        elif index_file_is_symlink "$PLUGIN_INDEX_FILE"; then
          echo "ERROR: $plugin/$file is a symlink in the index, should be a copy"
          OUT_OF_SYNC=1
        elif ! index_file_exists "$SHARED_INDEX_FILE" || ! index_files_equal "$SHARED_INDEX_FILE" "$PLUGIN_INDEX_FILE"; then
          echo "ERROR: $plugin/$file differs from shared/$file in the index"
          OUT_OF_SYNC=1
        fi
        continue
      fi

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

if [ "$USE_INDEX" = true ]; then
  LEGACY_MANIFEST_INDEX_FILE="scripts/legacy-skill-hashes.txt"
  LEGACY_HOOK_MANIFEST_INDEX_FILE="plugins/go-workflow/hooks/legacy-skill-hashes.txt"
  LEGACY_MANIFEST_CONTENT=$(git -C "$ROOT_DIR" show ':scripts/legacy-skill-hashes.txt') || {
    echo "ERROR: legacy skill hash manifest is missing from the index"
    exit 1
  }
  LEGACY_HOOK_MANIFEST_CONTENT=$(git -C "$ROOT_DIR" show ':plugins/go-workflow/hooks/legacy-skill-hashes.txt') || {
    echo "ERROR: legacy hook skill hash manifest is missing from the index"
    exit 1
  }
fi

if [ "$USE_INDEX" = false ] && { [ ! -f "$LEGACY_MANIFEST" ] || [ ! -f "$LEGACY_HOOK_MANIFEST" ]; }; then
  echo "ERROR: legacy skill hash manifest is missing"
  OUT_OF_SYNC=1
elif [ "$USE_INDEX" = true ] && ! index_files_equal "$LEGACY_MANIFEST_INDEX_FILE" "$LEGACY_HOOK_MANIFEST_INDEX_FILE"; then
  echo "ERROR: legacy skill hash manifests differ"
  OUT_OF_SYNC=1
elif [ "$USE_INDEX" = false ] && ! cmp -s "$LEGACY_MANIFEST" "$LEGACY_HOOK_MANIFEST"; then
  echo "ERROR: legacy skill hash manifests differ"
  OUT_OF_SYNC=1
else
  if [ "$USE_INDEX" = true ]; then
    SKILL_FILES=$(git -C "$ROOT_DIR" ls-files 'plugins/*/skills/*/SKILL.md')
  else
    SKILL_FILES=$(printf '%s\n' "$PLUGINS_DIR"/*/skills/*/SKILL.md)
  fi
  while IFS= read -r skill_file; do
    [ -n "$skill_file" ] || continue
    if [ "$USE_INDEX" = true ]; then
      skill_name="$(basename "$(dirname "$skill_file")")"
      skill_hash="$(sha256_index_file "$skill_file")"
    else
      [ -f "$skill_file" ] || continue
      skill_name="$(basename "$(dirname "$skill_file")")"
      skill_hash="$(sha256_file "$skill_file")"
    fi
    pair="$skill_hash $skill_name"
    if [ "$USE_INDEX" = true ]; then
      PAIR_PRESENT=$(awk -v pair="$pair" '$0 == pair { found = 1 } END { print found ? "true" : "false" }' <<< "$LEGACY_MANIFEST_CONTENT")
    elif awk -v pair="$pair" '$0 == pair { found = 1 } END { exit found ? 0 : 1 }' "$LEGACY_MANIFEST"; then
      PAIR_PRESENT=true
    else
      PAIR_PRESENT=false
    fi
    if [ "$PAIR_PRESENT" != true ]; then
      echo "ERROR: legacy skill hash manifest missing current skill hash: $pair"
      OUT_OF_SYNC=1
    fi
  done <<< "$SKILL_FILES"
fi

if [ $OUT_OF_SYNC -eq 1 ]; then
  echo ""
  echo "Files are out of sync! Run the applicable sync or legacy hash regeneration script."
  exit 1
else
  echo "All shared files are in sync."
  exit 0
fi
