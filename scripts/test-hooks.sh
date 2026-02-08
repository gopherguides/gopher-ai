#!/bin/bash
# Verify hooks.json files are valid and referenced scripts exist
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "=== Hook Tests ==="

# Find all hooks.json files
HOOK_FILES=$(find "$ROOT_DIR/plugins" -name "hooks.json" -type f 2>/dev/null | sort)
TOTAL=0

for hook_file in $HOOK_FILES; do
  TOTAL=$((TOTAL + 1))
  PLUGIN_DIR=$(dirname "$hook_file")
  REL_PATH="${hook_file#$ROOT_DIR/}"

  # Test: hooks.json is valid JSON
  echo -n "  $REL_PATH is valid JSON... "
  if ! jq . "$hook_file" >/dev/null 2>&1; then
    echo "FAIL"
    ERRORS=$((ERRORS + 1))
    continue
  fi
  echo "OK"

  # Test: All referenced command scripts exist
  # Extract command paths from hooks.json (they use ${CLAUDE_PLUGIN_ROOT} prefix)
  COMMANDS=$(jq -r '.. | .command? // empty' "$hook_file" 2>/dev/null | sort -u)

  for cmd in $COMMANDS; do
    # Replace ${CLAUDE_PLUGIN_ROOT} with the actual plugin directory (parent of hooks/)
    ACTUAL_PATH=$(echo "$cmd" | sed "s|\${CLAUDE_PLUGIN_ROOT}|$(dirname "$PLUGIN_DIR")|g")

    echo -n "  Referenced script exists: ${cmd}... "
    if [ ! -f "$ACTUAL_PATH" ]; then
      echo "FAIL (not found: $ACTUAL_PATH)"
      ERRORS=$((ERRORS + 1))
    elif [ ! -x "$ACTUAL_PATH" ]; then
      echo "FAIL (not executable)"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK"
    fi
  done
done

echo ""
if [ $TOTAL -eq 0 ]; then
  echo "No hooks.json files found (skipped)."
  exit 0
fi

if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS hook test(s) failed"
  exit 1
else
  echo "All hook tests passed ($TOTAL hooks.json file(s))."
fi
