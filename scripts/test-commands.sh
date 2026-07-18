#!/bin/bash
# Verify all .md command files have valid YAML frontmatter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "=== Command File Tests ==="

"$ROOT_DIR/scripts/test-review-plan.sh"
"$ROOT_DIR/scripts/test-codex-review-model.sh"
"$ROOT_DIR/scripts/test-ship-ollama-model.sh"

# Find all command .md files
COMMAND_FILES=$(find "$ROOT_DIR/plugins" "$ROOT_DIR/shared" -path "*/commands/*.md" -type f 2>/dev/null | sort)
TOTAL=0
INVALID=""

for file in $COMMAND_FILES; do
  TOTAL=$((TOTAL + 1))
  REL_PATH="${file#$ROOT_DIR/}"

  # Check file starts with ---
  FIRST_LINE=$(head -1 "$file")
  if [ "$FIRST_LINE" != "---" ]; then
    INVALID="$INVALID\n  $REL_PATH (missing opening ---)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check for closing ---
  # Find the second --- (closing frontmatter)
  CLOSING_LINE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$file")
  if [ -z "$CLOSING_LINE" ]; then
    INVALID="$INVALID\n  $REL_PATH (missing closing ---)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter and check for description field
  FRONTMATTER=$(sed -n "2,$((CLOSING_LINE - 1))p" "$file")
  if ! echo "$FRONTMATTER" | grep -q 'description:'; then
    INVALID="$INVALID\n  $REL_PATH (missing description field)"
    ERRORS=$((ERRORS + 1))
    continue
  fi
done

echo -n "Codex fallback commands use the official package safely... "
UNSCOPED_CODEX=$(grep -RInE 'npx[^`]*codex' "$ROOT_DIR/plugins" | grep -v '@openai/codex' || true)
CODEX_COMMAND="$ROOT_DIR/plugins/llm-tools/commands/codex.md"
NONINTERACTIVE_CODEX_FILES=(
  "$ROOT_DIR/plugins/llm-tools/commands/review-loop.md"
  "$ROOT_DIR/plugins/llm-tools/commands/llm-compare.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
)
MISSING_INSTALLED_CHECK=""
for file in "${NONINTERACTIVE_CODEX_FILES[@]}"; do
  if ! grep -q 'command -v codex' "$file"; then
    MISSING_INSTALLED_CHECK="${file#"$ROOT_DIR"/}"
    break
  fi
done
MISSING_AUTH_GUIDANCE=""
AUTH_GUIDANCE_FILES=(
  "$ROOT_DIR/plugins/llm-tools/lib/review-loop/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/codex-fallback.md"
)
for file in "${AUTH_GUIDANCE_FILES[@]}"; do
  if ! grep -q 'ChatGPT sign-in or API-key authentication' "$file"; then
    MISSING_AUTH_GUIDANCE="${file#"$ROOT_DIR"/}"
    break
  fi
done

if [ -n "$UNSCOPED_CODEX" ]; then
  echo "FAIL (unscoped npm Codex invocation found)"
  echo "$UNSCOPED_CODEX"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_INSTALLED_CHECK" ]; then
  echo "FAIL (installed Codex preference missing from $MISSING_INSTALLED_CHECK)"
  ERRORS=$((ERRORS + 1))
elif grep -qE 'npx[^`]*@openai/codex' "${NONINTERACTIVE_CODEX_FILES[@]}"; then
  echo "FAIL (non-interactive workflow downloads Codex)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q 'CODEX_CMD="npx -y @openai/codex"' "$CODEX_COMMAND"; then
  echo "FAIL (accepted run-once fallback missing)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q '\*\*Abort\*\*.*without running Codex or downloading a package' "$CODEX_COMMAND"; then
  echo "FAIL (declined run-once behavior missing)"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_AUTH_GUIDANCE" ]; then
  echo "FAIL (Codex authentication guidance missing from $MISSING_AUTH_GUIDANCE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "tmux-start matches issue windows exactly... "
GOPHER_AI_TMUX_START_SOURCE_ONLY=true source "$ROOT_DIR/plugins/go-workflow/scripts/tmux-start.sh"
TMUX_MATCH_FAILURE=""
TMUX_CANONICAL="gopher-ai-issue-12-fix-window-match"
TMUX_LEGACY="gopher-ai-issue-12"

assert_tmux_match() {
  local description="$1"
  local expected="$2"
  local windows="$3"
  local actual

  actual=$(printf '%s\n' "$windows" | find_existing_window "$TMUX_CANONICAL" "$TMUX_LEGACY")
  if [ "$actual" != "$expected" ]; then
    TMUX_MATCH_FAILURE="$description: expected '$expected', got '$actual'"
  fi
}

assert_tmux_match "canonical match" "$TMUX_CANONICAL" "$TMUX_CANONICAL"
assert_tmux_match "numeric prefix collision" "" $'gopher-ai-issue-1-old\ngopher-ai-issue-120-old\ngopher-ai-issue-123-old'
assert_tmux_match "repository collision" "" "another-repo-issue-12-fix-window-match"
assert_tmux_match "no match" "" "unrelated-window"
assert_tmux_match "legacy match" "$TMUX_LEGACY" "$TMUX_LEGACY"
assert_tmux_match "canonical priority" "$TMUX_CANONICAL" $'gopher-ai-issue-12\ngopher-ai-issue-12-fix-window-match'

if [ -n "$TMUX_MATCH_FAILURE" ]; then
  echo "FAIL ($TMUX_MATCH_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "User-only workflows avoid blocked Skill-tool composition... "
TMUX_START_SCRIPT="$ROOT_DIR/plugins/go-workflow/scripts/tmux-start.sh"
COMPLETE_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
E2E_FINISH="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/mode-finish.md"
BLOCKED_COMPOSITION=$(rg -n 'Invoke `\$(start-issue|e2e-verify|ship)([ `])' "$COMPLETE_ISSUE_SKILL" "$E2E_FINISH" || true)

if [ -n "$BLOCKED_COMPOSITION" ]; then
  echo "FAIL"
  echo "$BLOCKED_COMPOSITION"
  ERRORS=$((ERRORS + 1))
elif ! rg -q 'Read `\$\{CLAUDE_PLUGIN_ROOT\}/skills/start-issue/SKILL[.]md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load start-issue directly)"
  ERRORS=$((ERRORS + 1))
elif ! rg -q 'Read `\$\{CLAUDE_PLUGIN_ROOT\}/skills/e2e-verify/SKILL[.]md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load e2e-verify directly)"
  ERRORS=$((ERRORS + 1))
elif ! rg -q 'skills/ship/SKILL[.]md' "$E2E_FINISH"; then
  echo "FAIL (e2e-verify does not load ship directly)"
  ERRORS=$((ERRORS + 1))
elif ! rg -q '"/go-workflow:start-issue \$ISSUE_NUM"' "$TMUX_START_SCRIPT"; then
  echo "FAIL (tmux-start does not send the Claude Code slash command)"
  ERRORS=$((ERRORS + 1))
elif rg -q '"\\\$start-issue \$ISSUE_NUM"' "$TMUX_START_SCRIPT"; then
  echo "FAIL (tmux-start still sends Codex syntax to Claude Code)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

if ! "$ROOT_DIR/scripts/test-go-web-templates.sh"; then
  ERRORS=$((ERRORS + 1))
fi

echo -n "Command files have valid YAML frontmatter... "
if [ $ERRORS -gt 0 ]; then
  echo "FAIL ($ERRORS of $TOTAL)"
  printf "$INVALID\n"
else
  echo "OK ($TOTAL commands)"
fi

echo ""

echo -n "Database templates keep initialization instance-scoped and leak-free... "
DB_TEMPLATE_FAILURE=""
DB_TEMPLATES=(
  "$ROOT_DIR/plugins/go-web/templates/db/database.postgres.go:goose.DialectPostgres"
  "$ROOT_DIR/plugins/go-web/templates/db/database.sqlite.go:goose.DialectSQLite3"
  "$ROOT_DIR/plugins/go-web/templates/db/database.mysql.go:goose.DialectMySQL"
)

for entry in "${DB_TEMPLATES[@]}"; do
  file="${entry%%:*}"
  dialect="${entry#*:}"
  open_line=$(grep -nE 'pool, err := pgxpool.New|conn, err := sql.Open' "$file" | head -1 | cut -d: -f1)
  cleanup_line=$(grep -nE 'defer func\(\)' "$file" | head -1 | cut -d: -f1)
  ping_line=$(grep -nE 'Ping(Context)?\(ctx\)' "$file" | head -1 | cut -d: -f1)
  migration_line=$(grep -nE 'db\.migrate\(ctx\)' "$file" | head -1 | cut -d: -f1)

  if [ -z "$open_line" ] || [ -z "$cleanup_line" ] || [ -z "$ping_line" ] || [ -z "$migration_line" ] ||
     [ "$cleanup_line" -le "$open_line" ] || [ "$cleanup_line" -ge "$ping_line" ] || [ "$cleanup_line" -ge "$migration_line" ]; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not guard every post-open failure with cleanup"
    break
  fi
  if ! grep -Fq "goose.NewProvider(" "$file" ||
     ! grep -Fq "$dialect" "$file" ||
     ! grep -Fq 'goose.WithDisableGlobalRegistry(true)' "$file" ||
     ! grep -Fq 'provider.Up(ctx)' "$file" ||
     ! grep -Fq 'fs.Sub(migrationsFS, "migrations")' "$file"; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not use a context-aware instance provider"
    break
  fi
  if ! grep -Fq 'func (db *DB) Close() error' "$file"; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not expose shutdown errors consistently"
    break
  fi
done

if [ -z "$DB_TEMPLATE_FAILURE" ] && grep -nE 'goose\.(SetBaseFS|SetDialect|Up)\(' "${DB_TEMPLATES[@]%%:*}" >/dev/null; then
  DB_TEMPLATE_FAILURE="database templates still mutate goose package globals"
fi
if [ -z "$DB_TEMPLATE_FAILURE" ] &&
   { ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close database: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.sqlite.go" ||
     ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close database: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.mysql.go" ||
     ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close migration connection: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.postgres.go"; }; then
  DB_TEMPLATE_FAILURE="database close errors are not preserved"
fi
if [ -z "$DB_TEMPLATE_FAILURE" ] &&
   { ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/main.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.postgres.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.sqlite.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.mysql.go"; }; then
  DB_TEMPLATE_FAILURE="generated shutdown call sites discard database close errors"
fi

if [ -n "$DB_TEMPLATE_FAILURE" ]; then
  echo "FAIL ($DB_TEMPLATE_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo ""

echo -n "Gemini image defaults and request tiers are valid... "
GEMINI_IMAGE_DIR="$ROOT_DIR/plugins/llm-tools/skills/gemini-image"
GEMINI_COMMAND="$ROOT_DIR/plugins/llm-tools/commands/gemini-image.md"

if grep -Rqs 'gemini-3\.1-flash-image-preview' "$GEMINI_IMAGE_DIR" "$GEMINI_COMMAND"; then
  echo "FAIL (retired preview model referenced)"
  ERRORS=$((ERRORS + 1))
else
  BUILD_BLOCK=$(mktemp /tmp/gemini-image-build-XXXXXX)
  awk '
    /^## Build Block/ { section=1 }
    section && /^```bash$/ { block=1; next }
    block && /^```$/ { exit }
    block { print }
  ' "$GEMINI_IMAGE_DIR/request-builder.md" > "$BUILD_BLOCK"

  DEFAULT_REQUEST=$(env -u GEMINI_MODEL -u GEMINI_SERVICE_TIER GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  UNSUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-3.1-flash-image GEMINI_SERVICE_TIER=priority GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  SUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=PRIORITY GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  INVALID_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=express GEMINI_IMAGE_SIZE=4K GEMINI_PROMPT=test bash "$BUILD_BLOCK")

  if ! grep -q 'os.environ.get("GEMINI_MODEL", "gemini-3\.1-flash-image")' "$GEMINI_IMAGE_DIR/request-builder.md"; then
    echo "FAIL (GA model is not the builder default)"
    ERRORS=$((ERRORS + 1))
  elif python3 - "$DEFAULT_REQUEST" "$UNSUPPORTED_REQUEST" "$SUPPORTED_REQUEST" "$INVALID_REQUEST" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as f:
    default_payload = json.load(f)
with open(sys.argv[2]) as f:
    unsupported_payload = json.load(f)
with open(sys.argv[3]) as f:
    supported_payload = json.load(f)
with open(sys.argv[4]) as f:
    invalid_payload = json.load(f)

assert "serviceTier" not in default_payload
assert "serviceTier" not in unsupported_payload
assert supported_payload["serviceTier"] == "priority"
assert "serviceTier" not in invalid_payload
assert "imageSize" not in invalid_payload["generationConfig"]["imageConfig"]
PYEOF
  then
    echo "OK"
  else
    echo "FAIL (generated serviceTier payload mismatch)"
    ERRORS=$((ERRORS + 1))
  fi

  rm -f "$BUILD_BLOCK" "$DEFAULT_REQUEST" "$UNSUPPORTED_REQUEST" "$SUPPORTED_REQUEST" "$INVALID_REQUEST"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS command file(s) have issues"
  exit 1
else
  echo "All command tests passed."
fi
