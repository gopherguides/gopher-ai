#!/bin/bash
# Verify $ship enforces its E2E and merge-strategy gates.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCAL_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
E2E_EXECUTION="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/e2e-test-execution.md"
SHIP_SKILL="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
MERGE_DOC="$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"
STATE_FIELDS="$ROOT_DIR/plugins/go-workflow/lib/ship/state-fields.md"
CI_WATCH="$ROOT_DIR/plugins/go-workflow/lib/ship/ci-watch.md"
RESUME_MESSAGES="$ROOT_DIR/plugins/go-workflow/lib/ship/resume-messages.json"
STOP_HOOK="$ROOT_DIR/plugins/go-workflow/hooks/stop-hook.sh"
LOOP_LIB="$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh"
COMPLETE_ISSUE="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"

ERRORS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

require_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -qE -- "$pattern" "$file"; then
    fail "$label"
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE -- "$pattern" "$file"; then
    fail "$label"
  fi
}

echo "=== Ship E2E Gate Tests ==="

require_text "$LOCAL_REVIEW" "E2E PREREQUISITE MISSING" \
  "ship local review must name the missing-dev-server blocker"
require_text "$LOCAL_REVIEW" "e2e_result.*blocked" \
  "ship local review must persist blocked E2E state"
require_text "$LOCAL_REVIEW" "No merge" \
  "ship local review must explicitly stop before merge"
require_text "$SHIP_SKILL" "E2E may be reused only when" \
  "ship skill must not document --skip-coverage as unconditional E2E skip"
require_text "$SHIP_SKILL" "e2e_result=blocked" \
  "ship skill must document blocked E2E state in the top-level phase summary"
require_text "$SHIP_SKILL" "skipped only because the[[:space:]]*$" \
  "ship completion criteria must limit E2E skip to non-UI/no-web cases"
reject_text "$LOCAL_REVIEW" "If server fails to start within 30s.*skip to Step 8\\. Do NOT block shipping" \
  "ship local review still silently skips when dev server is missing"
reject_text "$LOCAL_REVIEW" "E2E failures are informational, NEVER block" \
  "ship local review still documents E2E failures as non-blocking"
reject_text "$SHIP_SKILL" "skip coverage \\+ e2e phases entirely" \
  "ship skill still says --skip-coverage skips E2E entirely"
reject_text "$SHIP_SKILL" "E2E smoke tests passed \\(or skipped .*[Mm]CP unavailable" \
  "ship completion criteria still allows MCP-unavailable E2E skip"
require_text "$LOCAL_REVIEW" "browser-tool-call-failed" \
  "ship local review must distinguish runtime browser failures from absent tooling"
require_text "$E2E_EXECUTION" "server connects" \
  "e2e verification must distinguish connection from callability"
require_text "$E2E_EXECUTION" "first browser tool call fails" \
  "e2e verification must cover a connected server that fails on first use"
require_text "$E2E_EXECUTION" "E2E_RESULT='missing-browser-tooling'" \
  "e2e verification must map runtime browser failures to a blocking result"
require_text "$E2E_EXECUTION" "expected canonical or authentication redirect" \
  "e2e verification must allow expected navigation redirects"
reject_text "$E2E_EXECUTION" "A mismatch or call error" \
  "e2e verification must not classify every URL mismatch as missing tooling"

BROWSER_FAILURE_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-browser-failure-XXXXXX")
BROWSER_FAILURE_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-browser-failure-fixture-XXXXXX")
awk '
  /^### Record browser tool-call failure$/ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$LOCAL_REVIEW" > "$BROWSER_FAILURE_BLOCK"

mkdir -p "$BROWSER_FAILURE_TMP/.local/state"
printf '%s\n' \
  '{"e2e_required":"true","e2e_attempted":"false","e2e_result":"passed","e2e_skip_reason":"","e2e_pages_tested":5}' \
  > "$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json"

BROWSER_FAILURE_STATE=$(cd "$BROWSER_FAILURE_TMP" && \
  PAGES_TESTED=0 bash -c 'source "$1"' _ "$BROWSER_FAILURE_BLOCK" >/dev/null && \
  jq -c '{
    required: .e2e_required,
    attempted: .e2e_attempted,
    result: .e2e_result,
    reason: .e2e_skip_reason,
    pages: .e2e_pages_tested
  }' .local/state/ship.loop.local.json)

if [ "$BROWSER_FAILURE_STATE" != '{"required":"true","attempted":"true","result":"blocked","reason":"browser-tool-call-failed","pages":0}' ]; then
  fail "connected server first-call failure must persist blocked attempted state"
fi

printf '%s\n' \
  '{"e2e_required":"true","e2e_attempted":"true","e2e_result":"passed","e2e_skip_reason":"","e2e_pages_tested":2}' \
  > "$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json"

PARTIAL_BROWSER_FAILURE_STATE=$(cd "$BROWSER_FAILURE_TMP" && \
  PAGES_TESTED=2 bash -c 'source "$1"' _ "$BROWSER_FAILURE_BLOCK" >/dev/null && \
  jq -c '{result: .e2e_result, reason: .e2e_skip_reason, pages: .e2e_pages_tested}' \
    .local/state/ship.loop.local.json)

if [ "$PARTIAL_BROWSER_FAILURE_STATE" != '{"result":"blocked","reason":"browser-tool-call-failed","pages":2}' ]; then
  fail "mid-run browser failure must remain blocked and preserve inspected pages"
fi

rm -f "$BROWSER_FAILURE_BLOCK"
rm -rf "$BROWSER_FAILURE_TMP"

require_text "$SHIP_SKILL" "SHIP_MERGE_STRATEGY.*--squash.*--rebase.*--merge" \
  "ship skill must document explicit strategy before squash-first fallback"

require_text "$MERGE_DOC" "e2e_result.*blocked" \
  "ship merge phase must read blocked E2E state"
require_text "$MERGE_DOC" "E2E PREREQUISITE MISSING" \
  "ship merge phase must stop on blocked E2E state"
require_text "$MERGE_DOC" "Verification partial" \
  "ship summary must avoid unqualified verification-complete wording for partial E2E"
require_text "$MERGE_DOC" "MERGE_METHOD=\"\\\${SHIP_MERGE_STRATEGY:-}\"" \
  "ship merge phase must honor explicit merge strategy configuration"
require_text "$MERGE_DOC" "Configured merge strategy.*is not allowed" \
  "ship merge phase must fail when an explicit strategy is forbidden"
require_text "$MERGE_DOC" "gh pr merge \"\\\$PR_NUM\" --delete-branch" \
  "ship merge queues must use the queue-only CLI exception"
require_text "$MERGE_DOC" 'gh api --method PUT "repos/\{owner\}/\{repo\}/pulls/\$PR_NUM/merge"' \
  "ship ordinary merges must use the REST pull merge endpoint"
require_text "$MERGE_DOC" '-f sha="\$HEAD_SHA"' \
  "ship ordinary merges must pin the expected head SHA"
require_text "$MERGE_DOC" '\.merged == true' \
  "ship ordinary merges must validate the REST merged result"

MERGE_STRATEGY_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-merge-strategy-XXXXXX")
MERGE_FIXTURE_PLUGIN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-merge-fixture-XXXXXX")
MERGE_FIXTURE_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-merge-worktree-XXXXXX")
mkdir -p "$MERGE_FIXTURE_PLUGIN_ROOT/scripts"
cp "$ROOT_DIR/plugins/go-workflow/scripts/cleanup-loop.sh" "$MERGE_FIXTURE_PLUGIN_ROOT/scripts/cleanup-loop.sh"
awk '
  /^## 13c\./ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$MERGE_DOC" > "$MERGE_STRATEGY_BLOCK"

run_merge_strategy_fixture() {
  local label="$1"
  local configured_strategy="$2"
  local settings="$3"
  local expected_status="$4"
  local expected_output="$5"
  local output
  local status

  set +e
  output=$(CLAUDE_PLUGIN_ROOT="$MERGE_FIXTURE_PLUGIN_ROOT" MERGE_FIXTURE_WORKTREE="$MERGE_FIXTURE_WORKTREE" MERGE_TEST_SETTINGS="$settings" SHIP_MERGE_STRATEGY="$configured_strategy" bash -c '
    mkdir -p "$MERGE_FIXTURE_WORKTREE/.local/state"
    touch "$MERGE_FIXTURE_WORKTREE/.local/state/ship.loop.local.json"
    cd "$MERGE_FIXTURE_WORKTREE"
    gh() {
      jq -cn --argjson settings "$MERGE_TEST_SETTINGS" \
        "{owner:{login:\"example\"},name:\"project\",allow_merge_commit:\$settings.merge,allow_squash_merge:\$settings.squash,allow_rebase_merge:\$settings.rebase}"
    }
    source "$1"
    printf "%s" "$MERGE_METHOD"
  ' _ "$MERGE_STRATEGY_BLOCK" 2>&1)
  status=$?
  set -e

  if [ "$status" -ne "$expected_status" ] || [[ "$output" != *"$expected_output"* ]]; then
    fail "$label (status $status, output: $output)"
  fi
}

run_merge_strategy_fixture \
  "explicit squash must be selected" \
  "squash" \
  '{"merge":true,"squash":true,"rebase":true}' \
  0 \
  "squash"
run_merge_strategy_fixture \
  "explicit merge must be selected" \
  "merge" \
  '{"merge":true,"squash":true,"rebase":true}' \
  0 \
  "merge"
run_merge_strategy_fixture \
  "unconfigured repositories must default to squash" \
  "" \
  '{"merge":true,"squash":true,"rebase":true}' \
  0 \
  "squash"
run_merge_strategy_fixture \
  "forbidden explicit strategy must fail" \
  "merge" \
  '{"merge":false,"squash":true,"rebase":true}' \
  1 \
  "Configured merge strategy 'merge' is not allowed"
run_merge_strategy_fixture \
  "invalid explicit strategy must fail and clean up" \
  "invalid" \
  '{"merge":true,"squash":true,"rebase":true}' \
  1 \
  "Loop 'ship' cancelled"
run_merge_strategy_fixture \
  "forbidden explicit strategy must clean up" \
  "merge" \
  '{"merge":false,"squash":true,"rebase":true}' \
  1 \
  "Loop 'ship' cancelled"
run_merge_strategy_fixture \
  "repositories without an allowed strategy must fail and clean up" \
  "" \
  '{"merge":false,"squash":false,"rebase":false}' \
  1 \
  "Loop 'ship' cancelled"

rm -f "$MERGE_STRATEGY_BLOCK"
rm -rf "$MERGE_FIXTURE_PLUGIN_ROOT"
rm -rf "$MERGE_FIXTURE_WORKTREE"

require_text "$STATE_FIELDS" "blocked" \
  "ship state fields must document blocked E2E result"

require_text "$SHIP_SKILL" '\| `reviewing` \| Expired review recovery, then Step 9' \
  "ship re-entry must not resume an expired in-session review"
require_text "$SHIP_SKILL" '\| `review-required` \| Step 5' \
  "ship must preserve a not-yet-started review after a PR head shift"
require_text "$CI_WATCH" 'phase "review-required"' \
  "CI head shifts must request one new review without marking it in flight"
require_text "$SHIP_SKILL" "Never end a session with staged or committed-but-unpushed work" \
  "ship must make validated work durable before yielding"
require_text "$LOCAL_REVIEW" "Delegate synchronously" \
  "ship agent reviews must run synchronously"
require_text "$LOCAL_REVIEW" 'review_result="skipped"' \
  "ship must record headless agent review skips"
require_text "$RESUME_MESSAGES" "Do not start another review.*Commit the validated staged diff.*push every local commit.*non-draft PR" \
  "ship reviewing resume message must drive commit, push, and PR creation"
require_text "$COMPLETE_ISSUE" '`reviewing` → Phase 3' \
  "complete-issue must not resume an expired agent review"

CI_SHIFT_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-ci-shift-XXXXXX")
DIRTY_HEAD_SHIFT_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-dirty-head-shift-XXXXXX")
awk '
  /^## 10d\./ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$CI_WATCH" > "$CI_SHIFT_BLOCK"

git -C "$DIRTY_HEAD_SHIFT_TMP" init -q -b fixture
git -C "$DIRTY_HEAD_SHIFT_TMP" config user.name "Test User"
git -C "$DIRTY_HEAD_SHIFT_TMP" config user.email "test@example.com"
printf '%s\n' "clean" > "$DIRTY_HEAD_SHIFT_TMP/tracked.txt"
git -C "$DIRTY_HEAD_SHIFT_TMP" add tracked.txt
git -C "$DIRTY_HEAD_SHIFT_TMP" commit -q -m "test: initialize fixture"
printf '%s\n' "dirty" >> "$DIRTY_HEAD_SHIFT_TMP/tracked.txt"
mkdir -p "$DIRTY_HEAD_SHIFT_TMP/.local/state"
printf '%s\n' '{"phase":"ci-watch"}' > "$DIRTY_HEAD_SHIFT_TMP/.local/state/ship.loop.local.json"

set +e
DIRTY_HEAD_SHIFT_OUTPUT=$(cd "$DIRTY_HEAD_SHIFT_TMP" && \
  RESET_MARKER="$DIRTY_HEAD_SHIFT_TMP/reset-attempted" bash -c '
    github_pr() {
      printf "%s\n" '\''{"head":{"sha":"new-sha","ref":"fixture"}}'\''
    }
    git() {
      if [ "$1" = "fetch" ] || [ "$1" = "checkout" ]; then
        return 0
      fi
      if [ "$1" = "reset" ]; then
        printf "%s\n" "reset" > "$RESET_MARKER"
        return 0
      fi
      command git "$@"
    }
    HEAD_SHA="old-sha"
    PR_NUM=1
    source "$1"
  ' _ "$CI_SHIFT_BLOCK" 2>&1)
DIRTY_HEAD_SHIFT_STATUS=$?
set -e

if [ "$DIRTY_HEAD_SHIFT_STATUS" -ne 1 ]; then
  fail "dirty-tree head-shift recovery must return a blocking status"
fi
if [[ "$DIRTY_HEAD_SHIFT_OUTPUT" != *"working tree has uncommitted changes"* ]] || \
   [[ "$DIRTY_HEAD_SHIFT_OUTPUT" != *"Inspect ownership before synchronization"* ]]; then
  fail "dirty-tree head-shift recovery must surface ship's dirty-tree policy"
fi
if [ -f "$DIRTY_HEAD_SHIFT_TMP/reset-attempted" ]; then
  fail "dirty-tree head-shift recovery must stop before reset"
fi
if git -C "$DIRTY_HEAD_SHIFT_TMP" diff --quiet; then
  fail "dirty-tree head-shift recovery must preserve local changes"
fi
if ! jq -e '.phase == "ci-watch"' "$DIRTY_HEAD_SHIFT_TMP/.local/state/ship.loop.local.json" >/dev/null; then
  fail "dirty-tree head-shift recovery must not advance the ship phase"
fi

rm -f "$CI_SHIFT_BLOCK"
rm -rf "$DIRTY_HEAD_SHIFT_TMP"

HEADLESS_TMP=$(mktemp -d "${TMPDIR:-/tmp}/ship-headless-e2e-XXXXXX")
mkdir -p "$HEADLESS_TMP/.local/state" "$HEADLESS_TMP/hooks" "$HEADLESS_TMP/lib"
cp "$STOP_HOOK" "$HEADLESS_TMP/hooks/stop-hook.sh"
cp "$LOOP_LIB" "$HEADLESS_TMP/lib/loop-state.sh"
cat > "$HEADLESS_TMP/.local/state/ship.loop.local.json" <<'EOF'
{"loop_name":"ship","iteration":1,"max_iterations":50,"completion_promise":"SHIPPED","phase":"reviewing","original_prompt":"ship"}
EOF
HEADLESS_OUTPUT=$(cd "$HEADLESS_TMP" && printf '{"transcript_path":""}\n' | bash hooks/stop-hook.sh)
HEADLESS_STATE=$(jq -c '{phase,review_result,review_skip_reason}' \
  "$HEADLESS_TMP/.local/state/ship.loop.local.json")
rm -rf "$HEADLESS_TMP"

if ! printf '%s\n' "$HEADLESS_OUTPUT" | jq -e '
  .decision == "block" and
  (.systemMessage | test("Do not start another review")) and
  (.systemMessage | test("Commit the validated staged diff")) and
  (.systemMessage | test("push every local commit")) and
  (.systemMessage | test("non-draft PR"))
' >/dev/null; then
  fail "headless reviewing state must recover through commit, push, and PR creation"
fi

if [ "$HEADLESS_STATE" != '{"phase":"pushing","review_result":"void","review_skip_reason":"session-boundary"}' ]; then
  fail "headless reviewing state must become a non-resumable pushing state"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS ship E2E gate issue(s)"
  exit 1
fi

echo "All ship E2E gate tests passed."
