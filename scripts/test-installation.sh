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

# Test 6: Plugin plugin.json versions match marketplace versions
echo -n "Plugin plugin.json versions match marketplace... "
PLUGIN_JSON_MISMATCHES=""
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  NAME=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  EXPECTED_VER=$(jq -r ".plugins[$i].version" "$MARKETPLACE")
  PLUGIN_JSON="plugins/$NAME/.claude-plugin/plugin.json"
  if [ -f "$PLUGIN_JSON" ]; then
    ACTUAL_VER=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)
    if [ -n "$ACTUAL_VER" ] && [ "$ACTUAL_VER" != "$EXPECTED_VER" ]; then
      PLUGIN_JSON_MISMATCHES="$PLUGIN_JSON_MISMATCHES $NAME(plugin.json:$ACTUAL_VER!=marketplace:$EXPECTED_VER)"
    fi
  fi
done
if [ -n "$PLUGIN_JSON_MISMATCHES" ]; then
  echo "FAIL:$PLUGIN_JSON_MISMATCHES"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Codex distribution builds... "
if ! "$ROOT_DIR/scripts/build-universal.sh" >/tmp/gopher-ai-build.log 2>&1; then
  echo "FAIL"
  sed -n '1,120p' /tmp/gopher-ai-build.log
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

CODEX_MARKETPLACE="$ROOT_DIR/dist/codex/plugins/marketplace.json"
echo -n "Codex marketplace is valid JSON... "
if ! jq . "$CODEX_MARKETPLACE" >/dev/null 2>&1; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

CODEX_PLUGIN_COUNT=$(jq '.plugins | length' "$CODEX_MARKETPLACE")
echo -n "Codex repo install writes matching marketplace entries... "
TMP_REPO=$(mktemp -d)
if ! "$ROOT_DIR/scripts/install-codex.sh" --repo "$TMP_REPO" >/tmp/gopher-ai-install-repo.log 2>&1; then
  echo "FAIL"
  sed -n '1,120p' /tmp/gopher-ai-install-repo.log
  ERRORS=$((ERRORS + 1))
else
  REPO_MARKETPLACE="$TMP_REPO/.agents/plugins/marketplace.json"
  ACTUAL_COUNT=$(jq '.plugins | length' "$REPO_MARKETPLACE")
  BAD_PATHS=$(jq -r '.plugins[] | select(.source.path | startswith("./plugins/") | not) | .source.path' "$REPO_MARKETPLACE")
  MISSING_DIRS=""
  for i in $(seq 0 $((ACTUAL_COUNT - 1))); do
    PLUGIN_PATH=$(jq -r ".plugins[$i].source.path" "$REPO_MARKETPLACE")
    if [ ! -d "$TMP_REPO/${PLUGIN_PATH#./}" ]; then
      MISSING_DIRS="$MISSING_DIRS $PLUGIN_PATH"
    fi
  done
  if [ "$ACTUAL_COUNT" -ne "$CODEX_PLUGIN_COUNT" ] || [ -n "$BAD_PATHS" ] || [ -n "$MISSING_DIRS" ]; then
    echo "FAIL"
    [ "$ACTUAL_COUNT" -ne "$CODEX_PLUGIN_COUNT" ] && echo "expected $CODEX_PLUGIN_COUNT plugins, got $ACTUAL_COUNT"
    [ -n "$BAD_PATHS" ] && echo "bad plugin paths:$BAD_PATHS"
    [ -n "$MISSING_DIRS" ] && echo "missing plugin dirs:$MISSING_DIRS"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi
rm -rf "$TMP_REPO"

echo -n "Codex installer --cleanup --yes removes only matching skills... "
TMP_HOME=$(mktemp -d)
SKILLS_DIR="$TMP_HOME/.codex/skills"
mkdir -p "$SKILLS_DIR"
# Seed:
#   1. A gopher-ai skill name with matching frontmatter — should be removed.
#   2. A gopher-ai skill name with NON-matching frontmatter — should be kept
#      (user redefined a skill that happens to share a generic name).
#   3. A user-custom skill name — should be kept.
SEEDED_OWNED=""
SEEDED_DISGUISED=""
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  skill_name=$(basename "$skill_dir")
  if [ -z "$SEEDED_OWNED" ]; then
    SEEDED_OWNED="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    printf -- "---\nname: %s\ndescription: legacy gopher-ai install\n---\n\nbody\n" "$skill_name" > "$SKILLS_DIR/$skill_name/SKILL.md"
  elif [ -z "$SEEDED_DISGUISED" ]; then
    SEEDED_DISGUISED="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    printf -- "---\nname: my-personal-%s\ndescription: user override\n---\n\nbody\n" "$skill_name" > "$SKILLS_DIR/$skill_name/SKILL.md"
    break
  fi
done
mkdir -p "$SKILLS_DIR/user-custom-skill"
printf -- "---\nname: user-custom-skill\ndescription: stays\n---\n" > "$SKILLS_DIR/user-custom-skill/SKILL.md"

if ! HOME="$TMP_HOME" bash "$ROOT_DIR/scripts/install-codex.sh" --cleanup --yes >/tmp/gopher-ai-install-cleanup.log 2>&1; then
  echo "FAIL"
  sed -n '1,120p' /tmp/gopher-ai-install-cleanup.log
  ERRORS=$((ERRORS + 1))
elif [ -d "$SKILLS_DIR/$SEEDED_OWNED" ]; then
  echo "FAIL (seeded gopher-ai skill not removed: $SEEDED_OWNED)"
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$SKILLS_DIR/$SEEDED_DISGUISED" ]; then
  echo "FAIL (cleanup wrongly removed disguised user skill: $SEEDED_DISGUISED)"
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$SKILLS_DIR/user-custom-skill" ]; then
  echo "FAIL (cleanup wrongly removed user-custom-skill)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME"

echo -n "Codex --cleanup without --yes refuses to delete on non-tty... "
TMP_HOME=$(mktemp -d)
SKILLS_DIR="$TMP_HOME/.codex/skills"
mkdir -p "$SKILLS_DIR"
SEEDED_OWNED=""
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  skill_name=$(basename "$skill_dir")
  SEEDED_OWNED="$skill_name"
  mkdir -p "$SKILLS_DIR/$skill_name"
  printf -- "---\nname: %s\ndescription: legacy\n---\n" "$skill_name" > "$SKILLS_DIR/$skill_name/SKILL.md"
  break
done
# Pipe </dev/null so stdin is not a tty; expect non-zero exit and skill kept.
if HOME="$TMP_HOME" bash "$ROOT_DIR/scripts/install-codex.sh" --cleanup </dev/null >/tmp/gopher-ai-cleanup-noconfirm.log 2>&1; then
  echo "FAIL (should exit non-zero without --yes on non-tty)"
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$SKILLS_DIR/$SEEDED_OWNED" ]; then
  echo "FAIL (deleted skill without confirmation)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME"

echo -n "install-all.sh runs Codex cleanup without jq on minimal machine... "
TMP_HOME=$(mktemp -d)
mkdir -p "$TMP_HOME/.codex/skills"
SEEDED_OWNED=""
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  skill_name=$(basename "$skill_dir")
  SEEDED_OWNED="$skill_name"
  mkdir -p "$TMP_HOME/.codex/skills/$skill_name"
  printf -- "---\nname: %s\ndescription: legacy\n---\n" "$skill_name" > "$TMP_HOME/.codex/skills/$skill_name/SKILL.md"
  break
done
JQ_PATH="$(command -v jq 2>/dev/null || true)"
if [ -n "$JQ_PATH" ]; then
  JQ_DIR="$(dirname "$JQ_PATH")"
  SAFE_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^${JQ_DIR}\$" | tr '\n' ':' | sed 's/:$//')
  # Force Codex-only: no ~/.claude/ in TMP_HOME, and gemini binary won't be reachable.
  if HOME="$TMP_HOME" PATH="$SAFE_PATH" bash "$ROOT_DIR/scripts/install-all.sh" --force </dev/null >/tmp/gopher-ai-installall-nojq.log 2>&1; then
    if [ -d "$TMP_HOME/.codex/skills/$SEEDED_OWNED" ]; then
      echo "FAIL (cleanup did not run)"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK"
    fi
  else
    echo "FAIL (install-all.sh exited non-zero on Codex-only/no-jq machine)"
    sed -n '1,40p' /tmp/gopher-ai-installall-nojq.log
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "SKIP (jq not installed)"
fi
rm -rf "$TMP_HOME"

echo -n "Codex --cleanup works without jq installed... "
TMP_HOME=$(mktemp -d)
SKILLS_DIR="$TMP_HOME/.codex/skills"
mkdir -p "$SKILLS_DIR"
# Hide jq via a PATH that excludes it. We deliberately keep core utilities by
# pointing PATH at the original location minus jq's directory.
JQ_PATH="$(command -v jq 2>/dev/null || true)"
if [ -n "$JQ_PATH" ]; then
  # Rebuild a sanitized PATH without jq's bin dir.
  JQ_DIR="$(dirname "$JQ_PATH")"
  SAFE_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v "^${JQ_DIR}\$" | tr '\n' ':' | sed 's/:$//')
  if HOME="$TMP_HOME" PATH="$SAFE_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --cleanup --yes >/tmp/gopher-ai-cleanup-nojq.log 2>&1; then
    echo "OK"
  else
    echo "FAIL (cleanup should not require jq)"
    sed -n '1,40p' /tmp/gopher-ai-cleanup-nojq.log
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "SKIP (jq not installed locally)"
fi
rm -rf "$TMP_HOME"

echo -n "Codex --user mode is rejected with migration message... "
if HOME="$(mktemp -d)" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-user-rejected.log 2>&1; then
  echo "FAIL (--user should exit non-zero)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q "removed" /tmp/gopher-ai-user-rejected.log; then
  echo "FAIL (no migration message)"
  sed -n '1,40p' /tmp/gopher-ai-user-rejected.log
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Build no longer emits dist/codex/skills/... "
if [ -d "$ROOT_DIR/dist/codex/skills" ]; then
  echo "FAIL (dist/codex/skills/ still exists after build)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS test(s) failed"
  exit 1
else
  echo "All installation tests passed."
fi
