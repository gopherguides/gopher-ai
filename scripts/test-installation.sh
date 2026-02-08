#!/bin/bash
# Verify marketplace.json is valid, all plugins referenced exist, and plugin.json files are valid
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

MARKETPLACE="$ROOT_DIR/.claude-plugin/marketplace.json"
ERRORS=0

echo "=== Plugin Installation Tests ==="

# Test 1: marketplace.json exists and is valid JSON
echo -n "marketplace.json is valid JSON... "
if ! jq . "$MARKETPLACE" >/dev/null 2>&1; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

# Test 2: marketplace.json has required fields
echo -n "marketplace.json has required fields... "
MISSING=""
for field in name metadata plugins; do
  if ! jq -e ".$field" "$MARKETPLACE" >/dev/null 2>&1; then
    MISSING="$MISSING $field"
  fi
done
if [ -n "$MISSING" ]; then
  echo "FAIL (missing:$MISSING)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

# Test 3: All referenced plugins exist
echo -n "All referenced plugin directories exist... "
PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE")
MISSING_PLUGINS=""
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  SOURCE=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
  PLUGIN_DIR="$ROOT_DIR/$SOURCE"
  if [ ! -d "$PLUGIN_DIR" ]; then
    NAME=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
    MISSING_PLUGINS="$MISSING_PLUGINS $NAME($SOURCE)"
  fi
done
if [ -n "$MISSING_PLUGINS" ]; then
  echo "FAIL (missing:$MISSING_PLUGINS)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK ($PLUGIN_COUNT plugins)"
fi

# Test 4: Each plugin has a valid plugin.json
echo -n "All plugins have valid plugin.json... "
INVALID_PLUGINS=""
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  SOURCE=$(jq -r ".plugins[$i].source" "$MARKETPLACE")
  NAME=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  PLUGIN_JSON="$ROOT_DIR/$SOURCE/.claude-plugin/plugin.json"
  if [ ! -f "$PLUGIN_JSON" ]; then
    INVALID_PLUGINS="$INVALID_PLUGINS $NAME(missing)"
  elif ! jq . "$PLUGIN_JSON" >/dev/null 2>&1; then
    INVALID_PLUGINS="$INVALID_PLUGINS $NAME(invalid)"
  fi
done
if [ -n "$INVALID_PLUGINS" ]; then
  echo "FAIL:$INVALID_PLUGINS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

# Test 5: Plugin versions match marketplace version
echo -n "Plugin versions are consistent... "
MARKETPLACE_VER=$(jq -r '.metadata.version' "$MARKETPLACE")
VERSION_MISMATCHES=""
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  NAME=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  PLUGIN_VER=$(jq -r ".plugins[$i].version" "$MARKETPLACE")
  if [ "$PLUGIN_VER" != "$MARKETPLACE_VER" ]; then
    VERSION_MISMATCHES="$VERSION_MISMATCHES $NAME($PLUGIN_VER!=$MARKETPLACE_VER)"
  fi
done
if [ -n "$VERSION_MISMATCHES" ]; then
  echo "FAIL:$VERSION_MISMATCHES"
  ERRORS=$((ERRORS + 1))
else
  echo "OK (all v$MARKETPLACE_VER)"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS test(s) failed"
  exit 1
else
  echo "All installation tests passed."
fi
