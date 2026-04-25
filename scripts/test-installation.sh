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

echo -n "Codex installer --cleanup --yes removes only owned skills... "
TMP_HOME=$(mktemp -d)
SKILLS_DIR="$TMP_HOME/.codex/skills"
mkdir -p "$SKILLS_DIR"
# Seed four scenarios:
#   1. SEEDED_OWNED         — gopher-ai name + matching content (gopher-ai SKILL.md verbatim)
#                             → MUST be removed.
#   2. SEEDED_NAME_DRIFT    — gopher-ai name + non-matching frontmatter name
#                             → MUST be kept (frontmatter check is the first gate).
#   3. SEEDED_CONTENT_DRIFT — gopher-ai name + matching frontmatter name + DIFFERENT content
#                             → MUST be kept (content fingerprint catches user-authored
#                             skills with generic names like `commit` or `ship`).
#   4. user-custom-skill    — unrelated name
#                             → MUST be kept.
SEEDED_OWNED=""
SEEDED_NAME_DRIFT=""
SEEDED_CONTENT_DRIFT=""
COUNT=0
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  skill_name=$(basename "$skill_dir")
  # Skip support directories under skills/ that are not actual skills (e.g.
  # plugins/go-workflow/skills/coverage/ holds shared docs, not a SKILL.md).
  [ -f "$skill_dir/SKILL.md" ] || continue
  COUNT=$((COUNT + 1))
  if [ -z "$SEEDED_OWNED" ]; then
    SEEDED_OWNED="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    # Copy verbatim so content matches a current shipped version.
    cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
  elif [ -z "$SEEDED_NAME_DRIFT" ]; then
    SEEDED_NAME_DRIFT="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    printf -- "---\nname: my-personal-%s\ndescription: user override\n---\n\nbody\n" "$skill_name" > "$SKILLS_DIR/$skill_name/SKILL.md"
  elif [ -z "$SEEDED_CONTENT_DRIFT" ]; then
    SEEDED_CONTENT_DRIFT="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    # Frontmatter name matches dir name (a user could plausibly write this for
    # a generic name like `commit`), but content is NOT any version we shipped.
    printf -- "---\nname: %s\ndescription: my own custom skill\n---\n\n# My %s\n\nUnrelated body content.\n" "$skill_name" "$skill_name" > "$SKILLS_DIR/$skill_name/SKILL.md"
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
  echo "FAIL (owned gopher-ai skill not removed: $SEEDED_OWNED)"
  sed -n '1,40p' /tmp/gopher-ai-install-cleanup.log
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$SKILLS_DIR/$SEEDED_NAME_DRIFT" ]; then
  echo "FAIL (cleanup wrongly removed name-drifted user skill: $SEEDED_NAME_DRIFT)"
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$SKILLS_DIR/$SEEDED_CONTENT_DRIFT" ]; then
  echo "FAIL (cleanup wrongly removed content-drifted user skill: $SEEDED_CONTENT_DRIFT)"
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
  # Skip support directories under skills/ that are not actual skills (e.g.
  # plugins/go-workflow/skills/coverage/ holds shared docs, not a SKILL.md).
  [ -f "$skill_dir/SKILL.md" ] || continue
  SEEDED_OWNED="$skill_name"
  mkdir -p "$SKILLS_DIR/$skill_name"
  # Verbatim copy so content fingerprint check recognizes it as gopher-ai-owned.
  cp "$skill_dir/SKILL.md" "$SKILLS_DIR/$skill_name/SKILL.md"
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
  # Skip support directories under skills/ that are not actual skills (e.g.
  # plugins/go-workflow/skills/coverage/ holds shared docs, not a SKILL.md).
  [ -f "$skill_dir/SKILL.md" ] || continue
  SEEDED_OWNED="$skill_name"
  mkdir -p "$TMP_HOME/.codex/skills/$skill_name"
  # Verbatim copy so content fingerprint check recognizes it as gopher-ai-owned.
  cp "$skill_dir/SKILL.md" "$TMP_HOME/.codex/skills/$skill_name/SKILL.md"
  break
done
JQ_PATH="$(command -v jq 2>/dev/null || true)"
if [ -n "$JQ_PATH" ]; then
  # Build a controlled PATH that contains only the directories required for
  # the test — no jq, no gemini — so the test result reflects installer
  # behavior rather than what else happens to be on the developer's PATH.
  TMP_BIN=$(mktemp -d)
  # Note: jq and gemini are intentionally excluded to simulate a minimal
  # Codex-only machine. sha256sum, git, and sort are needed for the new
  # content-fingerprint cleanup logic.
  for cmd in bash sh awk sed grep find mkdir rm cp mktemp printf cat dirname basename tr head tail xargs sleep date wc sha256sum git sort uniq stat ln readlink; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -s "$cmd_path" "$TMP_BIN/$cmd"
  done
  if HOME="$TMP_HOME" PATH="$TMP_BIN" bash "$ROOT_DIR/scripts/install-all.sh" --force </dev/null >/tmp/gopher-ai-installall-nojq.log 2>&1; then
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
  rm -rf "$TMP_BIN"
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

echo -n "Codex --cleanup works in bootstrap mode (no .git, manifest only)... "
# Reproduces Cory's failure: install via curl one-liner pulls a tarball with
# no .git/. The skill content is from an OLD shipped version (pre-trim).
# Without the manifest, current-source-hash check would fail; with the
# manifest, the cleanup correctly identifies and removes the legacy install.
TMP_HOME=$(mktemp -d)
TMP_FAKE_ROOT=$(mktemp -d)
SKILLS_DIR="$TMP_HOME/.codex/skills"
mkdir -p "$SKILLS_DIR"
# Build a fake bootstrap root (mirrors what curl|tar produces): plugins/, scripts/,
# and the manifest, but NO .git/.
mkdir -p "$TMP_FAKE_ROOT/plugins" "$TMP_FAKE_ROOT/scripts"
cp -R "$ROOT_DIR/plugins"/. "$TMP_FAKE_ROOT/plugins/"
cp "$ROOT_DIR/scripts/install-codex.sh" "$TMP_FAKE_ROOT/scripts/"
cp "$ROOT_DIR/scripts/build-universal.sh" "$TMP_FAKE_ROOT/scripts/" 2>/dev/null || true
cp "$ROOT_DIR/scripts/legacy-skill-hashes.txt" "$TMP_FAKE_ROOT/scripts/"
SEEDED_OWNED=""
# Pick a hash from the manifest that is NOT the current SKILL.md content for
# any skill — that simulates a stale install. We do this by finding a skill
# whose manifest entry differs from the current file hash.
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  skill_name=$(basename "$skill_dir")
  # Skip support directories under skills/ that are not actual skills (e.g.
  # plugins/go-workflow/skills/coverage/ holds shared docs, not a SKILL.md).
  [ -f "$skill_dir/SKILL.md" ] || continue
  CURRENT_HASH=$(sha256sum "$skill_dir/SKILL.md" | awk '{print $1}')
  # Find a manifest entry for THIS skill whose hash differs from current — a
  # historical version of the same skill. Per-skill scoping matters: with the
  # manifest format `<hash> <skill_name>`, the cleanup only accepts a hash if
  # both fields match, so picking a hash from a different skill wouldn't
  # exercise the bootstrap-mode lookup correctly.
  HISTORICAL_HASH=$(awk -v cur="$CURRENT_HASH" -v sn="$skill_name" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 != cur && $2 == sn { print $1; exit }
  ' "$ROOT_DIR/scripts/legacy-skill-hashes.txt")
  [ -n "$HISTORICAL_HASH" ] || continue
  # Find a blob with this hash from git history and reconstruct it as a stale install.
  # The inner subshell exits as soon as a match is printed; no `head -1` needed.
  STALE_BLOB=$(cd "$ROOT_DIR" && git rev-list --objects --all 2>/dev/null \
    | awk '$2 ~ /^plugins\/[^/]+\/skills\/[^/]+\/SKILL\.md$/ {print $1, $2}' \
    | (
        while read blob path; do
          h=$(git cat-file blob "$blob" 2>/dev/null | sha256sum | awk '{print $1}')
          if [ "$h" = "$HISTORICAL_HASH" ] && [ "$(basename "$(dirname "$path")")" = "$skill_name" ]; then
            echo "$blob"
            exit 0
          fi
        done
      ))
  if [ -n "$STALE_BLOB" ]; then
    SEEDED_OWNED="$skill_name"
    mkdir -p "$SKILLS_DIR/$skill_name"
    (cd "$ROOT_DIR" && git cat-file blob "$STALE_BLOB") > "$SKILLS_DIR/$skill_name/SKILL.md"
    break
  fi
done
if [ -z "$SEEDED_OWNED" ]; then
  echo "SKIP (no historical-but-not-current SKILL.md found in manifest)"
else
  if ! HOME="$TMP_HOME" bash "$TMP_FAKE_ROOT/scripts/install-codex.sh" --cleanup --yes >/tmp/gopher-ai-bootstrap-cleanup.log 2>&1; then
    echo "FAIL"
    sed -n '1,40p' /tmp/gopher-ai-bootstrap-cleanup.log
    ERRORS=$((ERRORS + 1))
  elif [ -d "$SKILLS_DIR/$SEEDED_OWNED" ]; then
    echo "FAIL (stale gopher-ai skill not removed in bootstrap mode: $SEEDED_OWNED)"
    sed -n '1,40p' /tmp/gopher-ai-bootstrap-cleanup.log
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi
rm -rf "$TMP_HOME" "$TMP_FAKE_ROOT"

echo -n "Gemini agent files have valid YAML frontmatter... "
AGENT_ERRORS=""
for f in "$ROOT_DIR"/plugins/*/agents/*.md; do
  [ -f "$f" ] || continue
  if ! head -1 "$f" | grep -q '^---$'; then
    AGENT_ERRORS="$AGENT_ERRORS $f(no-opening)"
    continue
  fi
  # Frontmatter must be a closed YAML block with a `name:` line inside it.
  # Require at least two `---` markers AND a `name:` line that appears within
  # the first block (between the opening and closing delimiter).
  if ! awk '
    /^---$/ { c++; next }
    c == 1 && /^name:[[:space:]]/ { found = 1 }
    END { exit (found && c >= 2) ? 0 : 1 }
  ' "$f"; then
    AGENT_ERRORS="$AGENT_ERRORS $f(invalid-frontmatter)"
  fi
done
if [ -n "$AGENT_ERRORS" ]; then
  echo "FAIL:$AGENT_ERRORS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "legacy-skill-hashes.txt is in sync with git history... "
if [ ! -f "$ROOT_DIR/scripts/legacy-skill-hashes.txt" ]; then
  echo "FAIL (manifest missing — run scripts/regen-legacy-hashes.sh)"
  ERRORS=$((ERRORS + 1))
else
  EXPECTED=$(cd "$ROOT_DIR" && git rev-list --objects --all 2>/dev/null \
      | awk '$2 ~ /^plugins\/[^/]+\/skills\/[^/]+\/SKILL\.md$/ {print $1, $2}' \
      | while read blob path; do
          skill_name=$(basename "$(dirname "$path")")
          h=$(cd "$ROOT_DIR" && git cat-file blob "$blob" 2>/dev/null | sha256sum | awk '{print $1}')
          [ -n "$h" ] && echo "$h $skill_name"
        done | sort -u)
  ACTUAL=$(awk '/^[[:space:]]*#/{next} /^[[:space:]]*$/{next} {print}' "$ROOT_DIR/scripts/legacy-skill-hashes.txt" | sort -u)
  # The manifest must be a SUPERSET of expected (hash, skill_name) pairs.
  MISSING=$(comm -23 <(echo "$EXPECTED") <(echo "$ACTUAL"))
  if [ -n "$MISSING" ]; then
    echo "FAIL ($(echo "$MISSING" | wc -l | tr -d ' ') missing pairs — run scripts/regen-legacy-hashes.sh)"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK ($(echo "$ACTUAL" | wc -l | tr -d ' ') pairs)"
  fi
fi

echo -n "Bootstrap honors GOPHER_AI_ARCHIVE_URL override... "
# Regression test for #146 review finding: setting GOPHER_AI_ARCHIVE_URL must
# bypass the git-clone preference so callers can test PR tarballs / mirrors.
# This test runs install-codex.sh from a path WITHOUT scripts/build-universal.sh
# (so bootstrap_repo() runs), points GOPHER_AI_ARCHIVE_URL at a local tarball,
# and asserts the script logs "Bootstrap source: curl <archive>" — proving the
# archive path ran rather than the default git-clone path.
TMP_HOME=$(mktemp -d)
TMP_SCRIPT_DIR=$(mktemp -d)
TMP_ARCHIVE_DIR=$(mktemp -d)
cp "$ROOT_DIR/scripts/install-codex.sh" "$TMP_SCRIPT_DIR/install-codex.sh"
cp -R "$ROOT_DIR" "$TMP_ARCHIVE_DIR/gopher-ai-main"
tar -czf "$TMP_ARCHIVE_DIR/gopher-ai-main.tar.gz" -C "$TMP_ARCHIVE_DIR" gopher-ai-main
mkdir -p "$TMP_HOME/.codex/skills"
LOG_FILE=$(mktemp)
if HOME="$TMP_HOME" GOPHER_AI_ARCHIVE_URL="file://$TMP_ARCHIVE_DIR/gopher-ai-main.tar.gz" \
   bash "$TMP_SCRIPT_DIR/install-codex.sh" --cleanup --yes >"$LOG_FILE" 2>&1; then
  # Strict assertion: the bootstrap log line must show the archive path was used,
  # NOT the git-clone path. This guards against the regression from #146 round 1.
  if grep -q "Bootstrap source: curl file://$TMP_ARCHIVE_DIR/gopher-ai-main.tar.gz" "$LOG_FILE"; then
    echo "OK"
  elif grep -q "Bootstrap source: git clone" "$LOG_FILE"; then
    echo "FAIL (bootstrap silently cloned default repo, ignoring GOPHER_AI_ARCHIVE_URL)"
    sed -n '1,30p' "$LOG_FILE"
    ERRORS=$((ERRORS + 1))
  else
    echo "FAIL (no Bootstrap source log line found — install-codex.sh may have lost the trace echo)"
    sed -n '1,30p' "$LOG_FILE"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "FAIL (script exited non-zero with archive URL override)"
  sed -n '1,30p' "$LOG_FILE"
  ERRORS=$((ERRORS + 1))
fi
rm -rf "$TMP_HOME" "$TMP_SCRIPT_DIR" "$TMP_ARCHIVE_DIR"
rm -f "$LOG_FILE"

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
