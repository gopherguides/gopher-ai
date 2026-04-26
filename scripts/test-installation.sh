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

echo -n "install-all.sh fails cleanly when jq is missing... "
# install-all.sh requires jq for every platform now (including Codex --user,
# which reads marketplace.json for the version field). This test verifies the
# script reports a clear "missing jq" error rather than silently misbehaving.
TMP_HOME=$(mktemp -d)
mkdir -p "$TMP_HOME/.codex"
JQ_PATH="$(command -v jq 2>/dev/null || true)"
if [ -n "$JQ_PATH" ]; then
  TMP_BIN=$(mktemp -d)
  # Deliberately exclude jq and gemini from this controlled PATH.
  for cmd in bash sh awk sed grep find mkdir rm cp mktemp printf cat dirname basename tr head tail xargs sleep date wc sha256sum git sort uniq stat ln readlink; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -s "$cmd_path" "$TMP_BIN/$cmd"
  done
  set +e
  HOME="$TMP_HOME" PATH="$TMP_BIN" bash "$ROOT_DIR/scripts/install-all.sh" --force </dev/null >/tmp/gopher-ai-installall-nojq.log 2>&1
  EXIT=$?
  set -e
  if [ "$EXIT" -eq 0 ]; then
    echo "FAIL (install-all.sh should error when jq is missing)"
    ERRORS=$((ERRORS + 1))
  elif ! grep -q "jq" /tmp/gopher-ai-installall-nojq.log; then
    echo "FAIL (error message did not mention jq)"
    sed -n '1,20p' /tmp/gopher-ai-installall-nojq.log
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
  rm -rf "$TMP_BIN"
else
  echo "SKIP (jq not installed locally)"
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

echo -n "legacy-skill-hashes.txt matches git history exactly... "
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
  # Exact equality — the manifest is the ownership oracle for `--cleanup`,
  # so an extra (hash, skill_name) pair would expand what gets deleted.
  # Both missing and extra pairs are failures.
  MISSING=$(comm -23 <(echo "$EXPECTED") <(echo "$ACTUAL"))
  EXTRA=$(comm -13 <(echo "$EXPECTED") <(echo "$ACTUAL"))
  if [ -n "$MISSING" ] || [ -n "$EXTRA" ]; then
    echo "FAIL"
    [ -n "$MISSING" ] && echo "  missing $(echo "$MISSING" | wc -l | tr -d ' ') pair(s) — run scripts/regen-legacy-hashes.sh"
    [ -n "$EXTRA" ] && {
      echo "  $(echo "$EXTRA" | wc -l | tr -d ' ') extra pair(s) not in git history (potential ownership-oracle pollution):"
      echo "$EXTRA" | head -3 | sed 's/^/    /'
    }
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

echo -n "SessionStart hook auto-cleans legacy Codex skills... "
TMP_HOME=$(mktemp -d)
TMP_PLUGIN=$(mktemp -d)/go-workflow
mkdir -p "$TMP_HOME/.codex/skills" "$TMP_PLUGIN/hooks" "$TMP_PLUGIN/.claude-plugin"
cp "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/.claude-plugin/plugin.json" "$TMP_PLUGIN/.claude-plugin/"
SEEDED_OWNED=""
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name=$(basename "$skill_dir")
  SEEDED_OWNED="$skill_name"
  mkdir -p "$TMP_HOME/.codex/skills/$skill_name"
  cp "$skill_dir/SKILL.md" "$TMP_HOME/.codex/skills/$skill_name/SKILL.md"
  break
done
mkdir -p "$TMP_HOME/.codex/skills/user-custom-skill"
printf -- "---\nname: user-custom-skill\ndescription: stays\n---\n" > "$TMP_HOME/.codex/skills/user-custom-skill/SKILL.md"

CLAUDE_PLUGIN_ROOT="$TMP_PLUGIN" HOME="$TMP_HOME" bash "$TMP_PLUGIN/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-1.log 2>&1
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "FAIL (hook exited $HOOK_EXIT)"
  cat /tmp/gopher-ai-hook-1.log
  ERRORS=$((ERRORS + 1))
elif [ -d "$TMP_HOME/.codex/skills/$SEEDED_OWNED" ]; then
  echo "FAIL (owned skill not removed: $SEEDED_OWNED)"
  cat /tmp/gopher-ai-hook-1.log
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$TMP_HOME/.codex/skills/user-custom-skill" ]; then
  echo "FAIL (cleanup wrongly removed user-custom-skill)"
  ERRORS=$((ERRORS + 1))
elif ! ls "$TMP_HOME/.codex/.gopher-ai-cleanup-"* >/dev/null 2>&1; then
  echo "FAIL (marker file not written)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q "🧹 gopher-ai: removed" /tmp/gopher-ai-hook-1.log; then
  echo "FAIL (no summary printed to stderr)"
  cat /tmp/gopher-ai-hook-1.log
  ERRORS=$((ERRORS + 1))
else
  # Re-run: marker should gate; second run must produce no output and not re-scan.
  CLAUDE_PLUGIN_ROOT="$TMP_PLUGIN" HOME="$TMP_HOME" bash "$TMP_PLUGIN/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-2.log 2>&1
  if [ -s /tmp/gopher-ai-hook-2.log ]; then
    echo "FAIL (second run was not gated by marker — output produced)"
    cat /tmp/gopher-ai-hook-2.log
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi
rm -rf "$TMP_HOME" "$(dirname "$TMP_PLUGIN")"

echo -n "SessionStart hook is silent on clean ~/.codex/skills/... "
TMP_HOME=$(mktemp -d)
mkdir -p "$TMP_HOME/.codex/skills"
mkdir -p "$TMP_HOME/.codex/skills/user-custom-skill"
printf -- "---\nname: user-custom-skill\ndescription: stays\n---\n" > "$TMP_HOME/.codex/skills/user-custom-skill/SKILL.md"
CLAUDE_PLUGIN_ROOT="$ROOT_DIR/plugins/go-workflow" HOME="$TMP_HOME" \
  bash "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-clean.log 2>&1
if [ ! -d "$TMP_HOME/.codex/skills/user-custom-skill" ]; then
  echo "FAIL (cleanup wrongly removed user-custom-skill)"
  ERRORS=$((ERRORS + 1))
elif [ -s /tmp/gopher-ai-hook-clean.log ]; then
  echo "FAIL (hook printed output when there was nothing to clean)"
  cat /tmp/gopher-ai-hook-clean.log
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME"

echo -n "SessionStart hook works with shasum fallback (no sha256sum)... "
# Stock macOS doesn't have sha256sum — only shasum. This test simulates that
# environment by hiding sha256sum from PATH and verifying cleanup still works.
TMP_HOME=$(mktemp -d)
TMP_PLUGIN=$(mktemp -d)/go-workflow
mkdir -p "$TMP_HOME/.codex/skills" "$TMP_PLUGIN/hooks" "$TMP_PLUGIN/.claude-plugin"
cp "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/.claude-plugin/plugin.json" "$TMP_PLUGIN/.claude-plugin/"
SEEDED_OWNED=""
for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name=$(basename "$skill_dir")
  SEEDED_OWNED="$skill_name"
  mkdir -p "$TMP_HOME/.codex/skills/$skill_name"
  cp "$skill_dir/SKILL.md" "$TMP_HOME/.codex/skills/$skill_name/SKILL.md"
  break
done
# Build a controlled PATH that has shasum and openssl available, but NOT sha256sum.
# This simulates stock macOS.
SHASUM_PATH="$(command -v shasum 2>/dev/null || true)"
if [ -z "$SHASUM_PATH" ]; then
  echo "SKIP (shasum not installed locally — cannot simulate macOS)"
else
  TMP_BIN=$(mktemp -d)
  for cmd in bash sh awk sed grep find mkdir rm cp mktemp printf cat dirname basename tr head tail sort uniq stat shasum; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -s "$cmd_path" "$TMP_BIN/$cmd"
  done
  # Deliberately do NOT link sha256sum.
  if CLAUDE_PLUGIN_ROOT="$TMP_PLUGIN" HOME="$TMP_HOME" PATH="$TMP_BIN" \
     bash "$TMP_PLUGIN/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-shasum.log 2>&1; then
    if [ -d "$TMP_HOME/.codex/skills/$SEEDED_OWNED" ]; then
      echo "FAIL (skill not removed when only shasum is available)"
      cat /tmp/gopher-ai-hook-shasum.log
      ERRORS=$((ERRORS + 1))
    else
      echo "OK"
    fi
  else
    echo "FAIL (hook errored without sha256sum)"
    cat /tmp/gopher-ai-hook-shasum.log
    ERRORS=$((ERRORS + 1))
  fi
  rm -rf "$TMP_BIN"
fi
rm -rf "$TMP_HOME" "$(dirname "$TMP_PLUGIN")"

echo -n "regen-legacy-hashes.sh refuses to run on a shallow clone... "
TMP_REPO=$(mktemp -d)
# Make a real shallow clone — --no-local disables git's local-clone optimization
# that would otherwise hardlink the full object database and ignore --depth.
if git clone --depth=1 --no-local --quiet "$ROOT_DIR" "$TMP_REPO/repo" 2>/dev/null; then
  # Use the working-tree version of regen-legacy-hashes.sh (so the test sees
  # uncommitted edits) but execute it against the shallow clone.
  cp "$ROOT_DIR/scripts/regen-legacy-hashes.sh" "$TMP_REPO/repo/scripts/regen-legacy-hashes.sh"
  if ! bash "$TMP_REPO/repo/scripts/regen-legacy-hashes.sh" >/tmp/gopher-ai-shallow.log 2>&1; then
    if grep -q -i "shallow" /tmp/gopher-ai-shallow.log; then
      echo "OK"
    else
      echo "FAIL (exited non-zero but didn't mention shallow)"
      sed -n '1,15p' /tmp/gopher-ai-shallow.log
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo "FAIL (regen succeeded on shallow clone — should have refused)"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "SKIP (could not create shallow test clone)"
fi
rm -rf "$TMP_REPO"

echo -n "SessionStart hook short-circuits when ~/.codex/ missing... "
TMP_HOME=$(mktemp -d)
# No ~/.codex/ at all — hook must exit 0 silently.
CLAUDE_PLUGIN_ROOT="$ROOT_DIR/plugins/go-workflow" HOME="$TMP_HOME" \
  bash "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-nocodex.log 2>&1
HOOK_EXIT=$?
if [ "$HOOK_EXIT" -ne 0 ]; then
  echo "FAIL (hook should exit 0 on no ~/.codex/)"
  ERRORS=$((ERRORS + 1))
elif [ -s /tmp/gopher-ai-hook-nocodex.log ]; then
  echo "FAIL (hook printed output when ~/.codex/ was missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME"

echo -n "Plugin-side manifest is in sync with scripts/ copy... "
if ! diff -q "$ROOT_DIR/scripts/legacy-skill-hashes.txt" "$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt" >/dev/null 2>&1; then
  echo "FAIL (run scripts/regen-legacy-hashes.sh)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

# --- Tests for the new marketplace-based --user install -------------------
#
# install-codex.sh --user uses Codex's marketplace + cache mechanism (the only
# install path Codex actually loads from). End-to-end testing requires the
# codex CLI; for unit-testing the cache layout + config edits, we stub codex
# with a no-op and pre-populate a fake marketplace clone that mirrors what
# `codex plugin marketplace add` would create.

# Helper: build a fake marketplace clone in $1/.codex/.tmp/marketplaces/gopher-ai/
# that mimics what `codex plugin marketplace add gopherguides/gopher-ai` produces.
seed_fake_marketplace_clone() {
  local home="$1"
  local clone="$home/.codex/.tmp/marketplaces/gopher-ai"
  mkdir -p "$clone"
  # Copy the current source plugins into plugins/<name>/, mirroring marketplace layout.
  mkdir -p "$clone/plugins"
  for plugin_dir in "$ROOT_DIR"/plugins/*; do
    [ -d "$plugin_dir/.codex-plugin" ] || continue
    cp -R "$plugin_dir" "$clone/plugins/"
  done
  cp -R "$ROOT_DIR/.agents" "$clone/" 2>/dev/null || true
  # Initialize a git repo so `git rev-parse --short=8 HEAD` works.
  git -C "$clone" init --quiet 2>/dev/null
  git -C "$clone" config user.email test@example.com
  git -C "$clone" config user.name test
  git -C "$clone" add -A
  git -C "$clone" commit --quiet -m "test seed" 2>/dev/null
  echo "$clone"
}

# Helper: build a stubbed PATH that has a no-op `codex` and core utilities.
build_stub_path() {
  local out="$1"
  local stub_dir
  stub_dir="$(mktemp -d)"
  cat > "$stub_dir/codex" <<'STUB'
#!/bin/sh
# No-op stub. install-codex.sh --user expects `codex plugin marketplace add` to
# produce ~/.codex/.tmp/marketplaces/gopher-ai/ — we pre-seed that directly in
# the test, so the stub just succeeds.
exit 0
STUB
  chmod +x "$stub_dir/codex"
  for cmd in bash sh awk sed grep find mkdir rm cp mktemp printf cat dirname basename tr head tail xargs sleep date wc sha256sum git sort uniq stat ln readlink jq comm touch chmod cut id env true false echo test; do
    cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
    [ -n "$cmd_path" ] && ln -s "$cmd_path" "$stub_dir/$cmd"
  done
  echo "$stub_dir"
}

echo -n "Codex --user populates marketplace cache with commit-hash subdir... "
TMP_HOME=$(mktemp -d)
seed_fake_marketplace_clone "$TMP_HOME" >/dev/null
STUB_PATH=$(build_stub_path "$TMP_HOME")
EXPECTED_HASH=$(git -C "$TMP_HOME/.codex/.tmp/marketplaces/gopher-ai" rev-parse --short=8 HEAD)
if ! HOME="$TMP_HOME" PATH="$STUB_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-user-install.log 2>&1; then
  echo "FAIL (--user exited non-zero)"
  sed -n '1,40p' /tmp/gopher-ai-user-install.log
  ERRORS=$((ERRORS + 1))
else
  EXPECTED_PLUGINS="go-dev go-web go-workflow gopher-guides llm-tools tailwind"
  MISSING=""
  for p in $EXPECTED_PLUGINS; do
    cached="$TMP_HOME/.codex/plugins/cache/gopher-ai/$p/$EXPECTED_HASH"
    if [ ! -f "$cached/.codex-plugin/plugin.json" ]; then
      MISSING="$MISSING $p"
    elif [ -d "$cached/.claude-plugin" ]; then
      MISSING="$MISSING $p(has-claude-plugin)"
    fi
  done
  if [ -n "$MISSING" ]; then
    echo "FAIL (cache populated incorrectly:$MISSING)"
    sed -n '1,30p' /tmp/gopher-ai-user-install.log
    ERRORS=$((ERRORS + 1))
  else
    echo "OK ($EXPECTED_HASH cached for 6 plugins)"
  fi
fi
rm -rf "$TMP_HOME" "$STUB_PATH"

echo -n "Codex --user adds [plugins.<name>@gopher-ai] entries to config.toml... "
TMP_HOME=$(mktemp -d)
seed_fake_marketplace_clone "$TMP_HOME" >/dev/null
STUB_PATH=$(build_stub_path "$TMP_HOME")
HOME="$TMP_HOME" PATH="$STUB_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/dev/null 2>&1
MISSING=""
for p in go-dev go-web go-workflow gopher-guides llm-tools tailwind; do
  if ! grep -qF "[plugins.\"${p}@gopher-ai\"]" "$TMP_HOME/.codex/config.toml" 2>/dev/null; then
    MISSING="$MISSING $p"
  fi
done
if [ -n "$MISSING" ]; then
  echo "FAIL (missing config entries:$MISSING)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$STUB_PATH"

echo -n "Codex --user is idempotent (re-running rebuilds cache cleanly)... "
TMP_HOME=$(mktemp -d)
seed_fake_marketplace_clone "$TMP_HOME" >/dev/null
STUB_PATH=$(build_stub_path "$TMP_HOME")
HOME="$TMP_HOME" PATH="$STUB_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/dev/null 2>&1
HASH=$(git -C "$TMP_HOME/.codex/.tmp/marketplaces/gopher-ai" rev-parse --short=8 HEAD)
echo "stale" > "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/$HASH/STALE_FILE"
# Also create an old commit-hash dir to verify it gets cleaned up.
mkdir -p "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/deadbeef"
echo "old version" > "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/deadbeef/SKILL.md"
HOME="$TMP_HOME" PATH="$STUB_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/dev/null 2>&1
if [ -f "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/$HASH/STALE_FILE" ]; then
  echo "FAIL (stale file survived re-install)"
  ERRORS=$((ERRORS + 1))
elif [ -d "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/deadbeef" ]; then
  echo "FAIL (old commit-hash dir not cleaned up)"
  ERRORS=$((ERRORS + 1))
elif [ ! -f "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/$HASH/.codex-plugin/plugin.json" ]; then
  echo "FAIL (re-install did not repopulate cache)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$STUB_PATH"

echo -n "Codex --user removes legacy direct ~/.codex/plugins/<name>/ installs... "
TMP_HOME=$(mktemp -d)
seed_fake_marketplace_clone "$TMP_HOME" >/dev/null
STUB_PATH=$(build_stub_path "$TMP_HOME")
# Plant a legacy unmarked direct install with our author email.
mkdir -p "$TMP_HOME/.codex/plugins/go-dev/.codex-plugin"
cp "$ROOT_DIR/plugins/go-dev/.codex-plugin/plugin.json" "$TMP_HOME/.codex/plugins/go-dev/.codex-plugin/"
# Plant a user-authored same-named plugin (must NOT be removed).
mkdir -p "$TMP_HOME/.codex/plugins/go-workflow/.codex-plugin"
printf '{\n  "name": "go-workflow",\n  "version": "9.9.9",\n  "author": { "email": "other@example.com" }\n}\n' \
  > "$TMP_HOME/.codex/plugins/go-workflow/.codex-plugin/plugin.json"
echo "user content" > "$TMP_HOME/.codex/plugins/go-workflow/USER_FILE"
HOME="$TMP_HOME" PATH="$STUB_PATH" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/dev/null 2>&1
if [ -d "$TMP_HOME/.codex/plugins/go-dev" ]; then
  echo "FAIL (gopher-ai legacy direct install not removed: go-dev)"
  ERRORS=$((ERRORS + 1))
elif [ ! -f "$TMP_HOME/.codex/plugins/go-workflow/USER_FILE" ]; then
  echo "FAIL (user-authored plugin wrongly removed: go-workflow)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$STUB_PATH"

echo -n "Codex --user fails cleanly when codex CLI is missing... "
TMP_HOME=$(mktemp -d)
TMP_BIN_NOCODEX=$(mktemp -d)
for cmd in bash sh awk sed grep find mkdir rm cp mktemp printf cat dirname basename tr head tail jq git; do
  cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
  [ -n "$cmd_path" ] && ln -s "$cmd_path" "$TMP_BIN_NOCODEX/$cmd"
done
# Deliberately do NOT link codex.
set +e
HOME="$TMP_HOME" PATH="$TMP_BIN_NOCODEX" bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-user-nocodex.log 2>&1
EXIT=$?
set -e
if [ "$EXIT" -eq 0 ]; then
  echo "FAIL (--user should error when codex is missing)"
  ERRORS=$((ERRORS + 1))
elif ! grep -qi "codex" /tmp/gopher-ai-user-nocodex.log; then
  echo "FAIL (error didn't mention codex)"
  cat /tmp/gopher-ai-user-nocodex.log
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$TMP_BIN_NOCODEX"

echo -n "json_author_email parses author.email, not first email anywhere... "
TMP_PLUGIN_JSON=$(mktemp)
cat > "$TMP_PLUGIN_JSON" <<'EOF'
{
  "name": "go-dev",
  "contributors": [{"email": "first-match@wrong.com"}],
  "author": {"name": "Gopher Guides", "email": "support@gopherguides.com"}
}
EOF
RESULT=$(awk '/^json_author_email\(\) \{/,/^\}/' "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" \
  | { cat; echo 'json_author_email "$1"'; } | bash -s "$TMP_PLUGIN_JSON" 2>/dev/null)
if [ "$RESULT" = "support@gopherguides.com" ]; then
  echo "OK"
else
  echo "FAIL (expected support@gopherguides.com, got: '$RESULT')"
  ERRORS=$((ERRORS + 1))
fi
rm -f "$TMP_PLUGIN_JSON"

echo -n "SessionStart hook removes ALL stale ~/.codex/plugins/<our-name>/ dirs... "
TMP_HOME=$(mktemp -d)
TMP_PLUGIN=$(mktemp -d)/go-workflow
mkdir -p "$TMP_HOME/.codex/plugins" "$TMP_PLUGIN/hooks" "$TMP_PLUGIN/.claude-plugin"
cp "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/.claude-plugin/plugin.json" "$TMP_PLUGIN/.claude-plugin/"
# Three scenarios:
#   1. UNMARKED gopher-ai plugin → MUST be removed
#   2. MARKED gopher-ai plugin (legacy from broken --user) → MUST be removed
#      (was the OLD hook's behavior to keep these, but now they're stale too)
#   3. User-authored same-named plugin with different author → MUST be kept
mkdir -p "$TMP_HOME/.codex/plugins/go-dev/.codex-plugin"
cp "$ROOT_DIR/plugins/go-dev/.codex-plugin/plugin.json" "$TMP_HOME/.codex/plugins/go-dev/.codex-plugin/"

mkdir -p "$TMP_HOME/.codex/plugins/llm-tools/.codex-plugin"
cp "$ROOT_DIR/plugins/llm-tools/.codex-plugin/plugin.json" "$TMP_HOME/.codex/plugins/llm-tools/.codex-plugin/"
echo "marker" > "$TMP_HOME/.codex/plugins/llm-tools/.gopher-ai-installed"

mkdir -p "$TMP_HOME/.codex/plugins/go-workflow/.codex-plugin"
printf '{\n  "name": "go-workflow",\n  "version": "0.1.0",\n  "author": { "email": "other@example.com" }\n}\n' \
  > "$TMP_HOME/.codex/plugins/go-workflow/.codex-plugin/plugin.json"

CLAUDE_PLUGIN_ROOT="$TMP_PLUGIN" HOME="$TMP_HOME" \
  bash "$TMP_PLUGIN/hooks/codex-cleanup-on-start.sh" >/tmp/gopher-ai-hook-plugins.log 2>&1
if [ -d "$TMP_HOME/.codex/plugins/go-dev" ]; then
  echo "FAIL (unmarked gopher-ai plugin not removed: go-dev)"
  cat /tmp/gopher-ai-hook-plugins.log
  ERRORS=$((ERRORS + 1))
elif [ -d "$TMP_HOME/.codex/plugins/llm-tools" ]; then
  echo "FAIL (marked legacy plugin not removed: llm-tools — should now be stale too)"
  cat /tmp/gopher-ai-hook-plugins.log
  ERRORS=$((ERRORS + 1))
elif [ ! -d "$TMP_HOME/.codex/plugins/go-workflow" ]; then
  echo "FAIL (user-authored plugin wrongly removed: go-workflow)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$(dirname "$TMP_PLUGIN")"

echo -n "SessionStart hook does NOT touch ~/.codex/plugins/cache/gopher-ai/... "
TMP_HOME=$(mktemp -d)
TMP_PLUGIN=$(mktemp -d)/go-workflow
mkdir -p "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/abc12345"
echo "test" > "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/abc12345/SKILL.md"
mkdir -p "$TMP_PLUGIN/hooks" "$TMP_PLUGIN/.claude-plugin"
cp "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$TMP_PLUGIN/hooks/"
cp "$ROOT_DIR/plugins/go-workflow/.claude-plugin/plugin.json" "$TMP_PLUGIN/.claude-plugin/"
CLAUDE_PLUGIN_ROOT="$TMP_PLUGIN" HOME="$TMP_HOME" \
  bash "$TMP_PLUGIN/hooks/codex-cleanup-on-start.sh" >/dev/null 2>&1
if [ ! -f "$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/abc12345/SKILL.md" ]; then
  echo "FAIL (cache wrongly cleared by hook)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$(dirname "$TMP_PLUGIN")"

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
