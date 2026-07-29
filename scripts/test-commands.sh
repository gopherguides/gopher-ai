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
"$ROOT_DIR/scripts/test-review-deep-actions.sh"

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
BLOCKED_COMPOSITION=$(awk '/Invoke `[$](start-issue|e2e-verify|ship)([ `])/' "$COMPLETE_ISSUE_SKILL" "$E2E_FINISH")

file_contains() {
  local needle="$1"
  local file="$2"
  awk -v needle="$needle" 'index($0, needle) { found = 1 } END { exit found ? 0 : 1 }' "$file"
}

if [ -n "$BLOCKED_COMPOSITION" ]; then
  echo "FAIL"
  echo "$BLOCKED_COMPOSITION"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Read `${CLAUDE_PLUGIN_ROOT}/skills/start-issue/SKILL.md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load start-issue directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Read `${CLAUDE_PLUGIN_ROOT}/skills/e2e-verify/SKILL.md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load e2e-verify directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'skills/ship/SKILL.md' "$E2E_FINISH"; then
  echo "FAIL (e2e-verify does not load ship directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'tmux send-keys -t "$WINDOW_NAME" "/go-workflow:start-issue $ISSUE_NUM" Enter' "$TMUX_START_SCRIPT"; then
  echo "FAIL (tmux-start does not send the Claude Code slash command)"
  ERRORS=$((ERRORS + 1))
elif file_contains 'tmux send-keys -t "$WINDOW_NAME" "\$start-issue $ISSUE_NUM" Enter' "$TMUX_START_SCRIPT"; then
  echo "FAIL (tmux-start still sends Codex syntax to Claude Code)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Shared go-workflow skills bind native capabilities by intent... "
GO_WORKFLOW_SKILLS="$ROOT_DIR/plugins/go-workflow/skills"
GO_WORKFLOW_LIB="$ROOT_DIR/plugins/go-workflow/lib"
DRIVER_INTERACTION="$GO_WORKFLOW_LIB/driver-interaction.md"
shopt -s nullglob
GO_WORKFLOW_MARKDOWN=(
  "$GO_WORKFLOW_SKILLS"/*/*.md
  "$GO_WORKFLOW_LIB"/*.md
  "$GO_WORKFLOW_LIB"/*/*.md
)
PLATFORM_TOOL_NAMES=$(awk '
  /(^|[^[:alnum:]_])(AskUserQuestion|EnterPlanMode|Agent|Task)([^[:alnum:]_]|$)/ {
    print FILENAME ":" FNR ":" $0
  }
' "${GO_WORKFLOW_MARKDOWN[@]}")
SHARED_ALLOWED_TOOLS=$(awk '
  /^allowed-tools:/ { print FILENAME ":" FNR ":" $0 }
' "$GO_WORKFLOW_SKILLS"/*/SKILL.md)
MISSING_DRIVER_BINDING=""
for skill_file in "$GO_WORKFLOW_SKILLS"/*/SKILL.md; do
  if ! file_contains 'driver-interaction.md' "$skill_file"; then
    MISSING_DRIVER_BINDING="${skill_file#"$ROOT_DIR"/}"
    break
  fi
done

if [ -n "$PLATFORM_TOOL_NAMES" ]; then
  echo "FAIL (platform-specific tool names found)"
  echo "$PLATFORM_TOOL_NAMES"
  ERRORS=$((ERRORS + 1))
elif [ -n "$SHARED_ALLOWED_TOOLS" ]; then
  echo "FAIL (shared skill frontmatter still contains a platform tool allowlist)"
  echo "$SHARED_ALLOWED_TOOLS"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_DRIVER_BINDING" ]; then
  echo "FAIL ($MISSING_DRIVER_BINDING does not load the driver interaction rules)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'native structured-input capability' "$DRIVER_INTERACTION" ||
     ! file_contains 'ask the concise question in the final' "$DRIVER_INTERACTION" ||
     ! file_contains 'pause_loop_for_driver' "$DRIVER_INTERACTION" ||
     ! file_contains 'resume_loop_after_driver' "$DRIVER_INTERACTION" ||
     ! file_contains 'Do not advance the phase' "$DRIVER_INTERACTION" ||
     ! file_contains 'emit a completion' "$DRIVER_INTERACTION"; then
  echo "FAIL (driver interaction rules do not preserve incomplete stop semantics)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Address-review stages only fix-cycle files... "
ADDRESS_REVIEW_FIX_CYCLE="$ROOT_DIR/plugins/go-workflow/skills/address-review/fix-cycle.md"
if file_contains 'git add -A' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (broad staging can capture unrelated worktree changes)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Stage only files modified during this fix cycle' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (owned-file staging policy missing)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'git status --porcelain -- "$TARGET_FILE"' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (pre-existing target-file changes are not guarded)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'git add -- "${OWNED_FILES[@]}"' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (owned-file staging command missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Address-review records incomplete bot approval outcomes... "
ADDRESS_REVIEW_WATCH_LOOP="$ROOT_DIR/plugins/go-workflow/skills/address-review/watch-loop.md"
if file_contains 'If "exit" → output `<done>COMPLETE</done>`' "$ADDRESS_REVIEW_WATCH_LOOP"; then
  echo "FAIL (timeout exit is mislabeled complete)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'approval_result' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'approval_reason' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'bot-approval-timeout' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'bot-approval-exhausted' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'APPROVAL_STATE_FILE="${STATE_FILE:-${LOOP_STATE_FILE:-}}"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'set_loop_field "$APPROVAL_STATE_FILE" "approval_result"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'completion_promise" "INCOMPLETE"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains '<done>INCOMPLETE</done>' "$ADDRESS_REVIEW_WATCH_LOOP"; then
  echo "FAIL (durable incomplete approval outcome contract missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Hard workflow invariants stop with machine-readable outcomes... "
INVARIANT_FAILURE=""

section_text() {
  local file="$1"
  local start="$2"
  local end="$3"

  awk -v start="$start" -v end="$end" '
    index($0, start) { active = 1 }
    active && index($0, end) && !index($0, start) { exit }
    active { print }
  ' "$file"
}

assert_invariant_section() {
  local label="$1"
  local file="$2"
  local start="$3"
  local end="$4"
  local reason="$5"
  local section

  section=$(section_text "$file" "$start" "$end")
  if [[ "$section" != *'WORKFLOW_RESULT=INCOMPLETE'* ]] ||
     [[ "$section" != *"WORKFLOW_REASON=$reason"* ]]; then
    INVARIANT_FAILURE="$label does not stop with reason $reason"
  fi
}

COVERAGE_ROUTER="$ROOT_DIR/plugins/go-workflow/lib/coverage/coverage-verification.md"
COVERAGE_GATE="$ROOT_DIR/plugins/go-workflow/lib/coverage/step-e-gate.md"
COVERAGE_GENERATION="$ROOT_DIR/plugins/go-workflow/lib/coverage/step-f-test-generation.md"
SHIP_SKILL="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
SHIP_CI="$ROOT_DIR/plugins/go-workflow/lib/ship/ci-watch.md"
SHIP_MERGE="$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"
SHIP_ADDRESS="$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md"
SHIP_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
COMMIT_SKILL="$ROOT_DIR/plugins/go-workflow/skills/commit/SKILL.md"
CREATE_PR_SKILL="$ROOT_DIR/plugins/go-workflow/skills/create-pr/SKILL.md"
WORKTREE_REMOVE="$ROOT_DIR/plugins/go-workflow/skills/worktree/remove.md"
E2E_REBASE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/rebase-and-build.md"
E2E_SKILL="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
ADDRESS_REBASE="$ROOT_DIR/plugins/go-workflow/skills/address-review/checkout-rebase.md"
ADDRESS_SKILL="$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md"
REVIEW_DEEP_FIX="$ROOT_DIR/plugins/go-workflow/skills/review-deep/fix-and-verify.md"
START_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/start-issue/SKILL.md"

assert_invariant_section "low coverage" "$COVERAGE_GATE" \
  "### Branch 3" "### Branch 4" "coverage-below-threshold"
assert_invariant_section "missing tests" "$COVERAGE_GATE" \
  "### Branch 4" "### Branch 5" "coverage-no-tests"
assert_invariant_section "coverage test generation" "$COVERAGE_GENERATION" \
  "## Persist count and return" "__END__" \
  "coverage-test-generation-failed"
assert_invariant_section "CI registration timeout" "$SHIP_CI" \
  "## 10b." "## 10c." "ci-checks-not-registered"
assert_invariant_section "commit default branch" "$COMMIT_SKILL" \
  "### Step 2:" "### Step 3:" "default-branch"
assert_invariant_section "create-pr default branch" "$CREATE_PR_SKILL" \
  "### Step 2:" "### Step 3:" "default-branch"
assert_invariant_section "unsafe worktree removal" "$WORKTREE_REMOVE" \
  "**Unsafe removal**" "### Step 5:" "unsafe-worktree"
assert_invariant_section "E2E rebase conflict" "$E2E_REBASE" \
  "### 1c." "### 1d." "rebase-conflict"
assert_invariant_section "address-review rebase conflict" "$ADDRESS_REBASE" \
  '**If `$BEHIND` > 0:**' "## 1c." "rebase-conflict"
assert_invariant_section "ship rebase conflict" "$SHIP_ADDRESS" \
  "## 12a." "## 12b." "rebase-conflict"
assert_invariant_section "E2E generation failure" "$E2E_REBASE" \
  "### 2a." "### 2b." "generation-failed"
assert_invariant_section "E2E verification failure" "$E2E_REBASE" \
  "### 2b." "### 2c." "verification-failed"
assert_invariant_section "E2E post-fix verification failure" "$E2E_SKILL" \
  "### Re-verify after fixes" "## Step 4:" "verification-failed"
assert_invariant_section "review-deep verification failure" "$REVIEW_DEEP_FIX" \
  "## Verification" "## Commit" "verification-failed"
assert_invariant_section "ship generation failure" "$SHIP_REVIEW" \
  "### Codegen drift check" "### Per-language verification" "generation-failed"
assert_invariant_section "ship verification failure" "$SHIP_REVIEW" \
  "### Per-language verification" "## Step 7.5" "verification-failed"

LOW_COVERAGE_SECTION=$(section_text "$COVERAGE_GATE" "### Branch 3" "### Branch 5")
CI_REGISTRATION_SECTION=$(section_text "$SHIP_CI" "## 10b." "## 10c.")
WORKTREE_UNSAFE_SECTION=$(section_text "$WORKTREE_REMOVE" "**Unsafe removal**" "### Step 5:")
SHIP_FINAL_CHECKS=$(section_text "$SHIP_MERGE" "## 13a." "## 13b.")
SHIP_MERGEABILITY=$(section_text "$SHIP_MERGE" "## 13d." "## 13e.")
REVIEW_DEEP_VERIFICATION=$(section_text "$REVIEW_DEEP_FIX" "## Verification" "## Commit")
E2E_BUILD_VERIFICATION=$(section_text "$E2E_REBASE" "### 2b." "### 2c.")

if [[ "$LOW_COVERAGE_SECTION" == *"AskUserQuestion"* ]] ||
   [[ "$LOW_COVERAGE_SECTION" == *"Proceed without"* ]]; then
  INVARIANT_FAILURE="coverage failure still offers a bypass"
elif [[ "$CI_REGISTRATION_SECTION" == *"AskUserQuestion"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" == *"proceed without CI"* ]]; then
  INVARIANT_FAILURE="CI registration timeout still offers a bypass"
elif [[ "$CI_REGISTRATION_SECTION" != *"ci_skip_reason=no-applicable-workflow"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" != *"WORKFLOW_REASON=ci-checks-not-registered"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" != *"WORKFLOW_REASON=ci-applicability-unknown"* ]]; then
  INVARIANT_FAILURE="CI registration does not distinguish inapplicable and missing checks"
elif [[ "$WORKTREE_UNSAFE_SECTION" == *"--force"* ]]; then
  INVARIANT_FAILURE="unsafe worktree removal still force-deletes"
elif [[ "$SHIP_FINAL_CHECKS" != *"WORKFLOW_REASON=unresolved-review-threads"* ]] ||
     [[ "$SHIP_FINAL_CHECKS" != *"WORKFLOW_REASON=human-changes-requested"* ]] ||
     [[ "$SHIP_FINAL_CHECKS" == *"ask how to proceed"* ]]; then
  INVARIANT_FAILURE="ship final review checks do not stop unconditionally"
elif [[ "$SHIP_MERGEABILITY" == *"AskUserQuestion"* ]] ||
     [[ "$SHIP_MERGEABILITY" != *"WORKFLOW_REASON=mergeability-unknown"* ]] ||
     [[ "$SHIP_MERGEABILITY" != *'| `MERGEABLE` | `UNSTABLE` | **STOP.'* ]]; then
  INVARIANT_FAILURE="ship mergeability states still permit an invalid merge"
elif file_contains "commit to main anyway" "$COMMIT_SKILL" ||
     file_contains "default branch. Inform the user and ask how to proceed" "$SHIP_SKILL"; then
  INVARIANT_FAILURE="default-branch workflow still offers a bypass"
elif file_contains "Proceed with fixes WITHOUT rebasing" "$SHIP_ADDRESS" ||
     file_contains "proceed without rebasing" "$SHIP_SKILL"; then
  INVARIANT_FAILURE="ship can continue after an unresolved rebase"
elif ! file_contains 'completion_promise" "INCOMPLETE"' "$ADDRESS_SKILL"; then
  INVARIANT_FAILURE="address-review rebase stops are not durable"
elif [[ "$REVIEW_DEEP_VERIFICATION" == *"|| true"* ]] ||
     [[ "$E2E_BUILD_VERIFICATION" == *"|| true"* ]]; then
  INVARIANT_FAILURE="verification failure is still ignored"
elif ! file_contains "cargo clippy --version" "$REVIEW_DEEP_FIX" ||
     ! file_contains "cargo clippy --version" "$SHIP_REVIEW"; then
  INVARIANT_FAILURE="Rust verification does not gate optional Clippy"
elif file_contains "Skipping codegen check" "$E2E_REBASE" ||
     file_contains "Skipping codegen check" "$SHIP_REVIEW"; then
  INVARIANT_FAILURE="generation failure is still ignored"
elif ! file_contains "Only source-free changes" "$COVERAGE_ROUTER"; then
  INVARIANT_FAILURE="coverage router does not constrain skip behavior"
elif file_contains 'Coverage verified or skipped (per `--skip-coverage` flag)' "$START_ISSUE_SKILL" ||
     file_contains 'execute the ship workflow with `--skip-coverage`' "$E2E_FINISH"; then
  INVARIANT_FAILURE="a completion path still waives changed-source coverage"
fi

if [ -n "$INVARIANT_FAILURE" ]; then
  echo "FAIL ($INVARIANT_FAILURE)"
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
