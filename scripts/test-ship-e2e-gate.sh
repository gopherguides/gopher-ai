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
ADDRESS_BOTS="$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md"

ERRORS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

require_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -qE -e "$pattern" "$file"; then
    fail "$label"
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE -e "$pattern" "$file"; then
    fail "$label"
  fi
}

ambiguous_output_names_files() {
  local output="$1"
  local owner_file="$2"
  local stray_file="$3"

  printf '%s\n' "$output" | grep -F 'Ambiguous linked-worktree loop state candidates' >/dev/null &&
    printf '%s\n' "$output" | grep -F "$owner_file" >/dev/null &&
    printf '%s\n' "$output" | grep -F "$stray_file" >/dev/null
}

validate_ship_address_review_contract() {
  local file="$1"

  grep -qF 'ADDRESS_REVIEW_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "address_review")' "$file" &&
    grep -qF 'initialize_workflow_state "$STATE_FILE" "$ADDRESS_REVIEW_STATE_PATH"' "$file" &&
    grep -qF 'Embedded Workflow Contract' "$file" &&
    grep -qF 'WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"' "$file" &&
    grep -qF 'unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH' "$file" &&
    grep -qF 'ADDRESS_REVIEW_RESULT=$(get_loop_field "$STATE_FILE" "result" "$ADDRESS_REVIEW_STATE_PATH")' "$file" &&
    grep -qF 'if [ "$ADDRESS_REVIEW_RESULT" != "complete" ]; then' "$file" &&
    grep -qF 'WORKFLOW_REASON="${ADDRESS_REVIEW_REASON:-address-review-incomplete}"' "$file" &&
    grep -qF 'stop before Step 12c' "$file"
}

echo "=== Ship E2E Gate Tests ==="

echo -n "Ship routes embedded address-review through a checked component result... "
if validate_ship_address_review_contract "$ADDRESS_BOTS"; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

MUTATED_ADDRESS_BOTS=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-mutated-address-bots-XXXXXX")
sed '/ADDRESS_REVIEW_RESULT=$(get_loop_field/d' "$ADDRESS_BOTS" > "$MUTATED_ADDRESS_BOTS"
echo -n "Address-review result assertion rejects an unchecked child mutation... "
if validate_ship_address_review_contract "$MUTATED_ADDRESS_BOTS"; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$MUTATED_ADDRESS_BOTS"

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
  '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","phase":"e2e-testing","completion_promise":"SHIPPED","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"e2e_required":"true","e2e_attempted":"false","e2e_result":"passed","e2e_skip_reason":"","e2e_pages_tested":5}' \
  > "$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json"

BROWSER_FAILURE_STATE=$(cd "$BROWSER_FAILURE_TMP" && \
  STATE_FILE="$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json" WORKFLOW_STATE_PATH='[]' PAGES_TESTED=0 \
  bash -c 'source "$1"; source "$2"' _ "$LOOP_LIB" "$BROWSER_FAILURE_BLOCK" >/dev/null && \
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
  '{"schema_version":2,"owner_workflow":"ship","loop_name":"ship","phase":"e2e-testing","completion_promise":"SHIPPED","terminal_promises":["SHIPPED","INCOMPLETE"],"components":{},"e2e_required":"true","e2e_attempted":"true","e2e_result":"passed","e2e_skip_reason":"","e2e_pages_tested":2}' \
  > "$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json"

PARTIAL_BROWSER_FAILURE_STATE=$(cd "$BROWSER_FAILURE_TMP" && \
  STATE_FILE="$BROWSER_FAILURE_TMP/.local/state/ship.loop.local.json" WORKFLOW_STATE_PATH='[]' PAGES_TESTED=2 \
  bash -c 'source "$1"; source "$2"' _ "$LOOP_LIB" "$BROWSER_FAILURE_BLOCK" >/dev/null && \
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
require_text "$MERGE_DOC" "gh pr merge \"\\\$PR_NUM\" --repo \"\\\$REPO_SLUG\" --delete-branch" \
  "ship merge queues must use the queue-only CLI exception"
require_text "$MERGE_DOC" 'gh api --method PUT "repos/\$REPO_SLUG/pulls/\$PR_NUM/merge"' \
  "ship ordinary merges must use the REST pull merge endpoint"
require_text "$MERGE_DOC" '-f sha="\$HEAD_SHA"' \
  "ship ordinary merges must pin the expected head SHA"
require_text "$MERGE_DOC" '\.merged == true' \
  "ship ordinary merges must validate the REST merged result"

MERGE_STRATEGY_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-merge-strategy-XXXXXX")
MERGE_FIXTURE_PLUGIN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-merge-fixture-XXXXXX")
MERGE_FIXTURE_WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-merge-worktree-XXXXXX")
mkdir -p "$MERGE_FIXTURE_PLUGIN_ROOT/lib"
cp "$LOOP_LIB" "$MERGE_FIXTURE_PLUGIN_ROOT/lib/loop-state.sh"
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
  output=$(CLAUDE_PLUGIN_ROOT="$MERGE_FIXTURE_PLUGIN_ROOT" ORIGINAL_REPO_ROOT="$MERGE_FIXTURE_WORKTREE" WORKTREE_PATH="$MERGE_FIXTURE_WORKTREE" REPO_SLUG="example/project" MERGE_FIXTURE_WORKTREE="$MERGE_FIXTURE_WORKTREE" MERGE_TEST_SETTINGS="$settings" SHIP_MERGE_STRATEGY="$configured_strategy" bash -c '
    mkdir -p "$MERGE_FIXTURE_WORKTREE/.local/state"
    STATE_FILE="$MERGE_FIXTURE_WORKTREE/.local/state/ship.loop.local.json"
    WORKFLOW_STATE_PATH="[]"
    SHIP_EMBEDDED=false
    jq -n "{schema_version:2,owner_workflow:\"ship\",loop_name:\"ship\",iteration:1,max_iterations:50,completion_promise:\"SHIPPED\",terminal_promises:[\"SHIPPED\",\"INCOMPLETE\"],phase:\"merging\",components:{}}" > "$STATE_FILE"
    cd "$MERGE_FIXTURE_WORKTREE"
    source "$CLAUDE_PLUGIN_ROOT/lib/loop-state.sh"
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
  "invalid explicit strategy must persist an incomplete terminal" \
  "invalid" \
  '{"merge":true,"squash":true,"rebase":true}' \
  1 \
  "<done>INCOMPLETE</done>"
run_merge_strategy_fixture \
  "forbidden explicit strategy must persist an incomplete terminal" \
  "merge" \
  '{"merge":false,"squash":true,"rebase":true}' \
  1 \
  "<done>INCOMPLETE</done>"
run_merge_strategy_fixture \
  "repositories without an allowed strategy must persist an incomplete terminal" \
  "" \
  '{"merge":false,"squash":false,"rebase":false}' \
  1 \
  "<done>INCOMPLETE</done>"

rm -f "$MERGE_STRATEGY_BLOCK"
rm -rf "$MERGE_FIXTURE_PLUGIN_ROOT"
rm -rf "$MERGE_FIXTURE_WORKTREE"

require_text "$STATE_FIELDS" "blocked" \
  "ship state fields must document blocked E2E result"

require_text "$SHIP_SKILL" '\| `reviewing` \| Expired review recovery, then Step 9' \
  "ship re-entry must not resume an expired in-session review"
require_text "$SHIP_SKILL" '\| `review-required` \| Step 5' \
  "ship must preserve a not-yet-started review after a PR head shift"
require_text "$CI_WATCH" 'set_loop_phase.*"review-required"' \
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
  RESET_MARKER="$DIRTY_HEAD_SHIFT_TMP/reset-attempted" \
  WORKTREE_PATH="$DIRTY_HEAD_SHIFT_TMP" \
  REPO_SLUG="example/project" \
  STATE_FILE="$DIRTY_HEAD_SHIFT_TMP/.local/state/ship.loop.local.json" bash -c '
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

SHIP_STATE_DOCS="
$SHIP_SKILL
$STATE_FIELDS
$LOCAL_REVIEW
$CI_WATCH
$MERGE_DOC
$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md
$ROOT_DIR/plugins/go-workflow/lib/ship/bot-watch.md
$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md
$ROOT_DIR/plugins/go-workflow/lib/ship/push-and-pr.md
"

validate_ship_state_contract() {
  local skill_file="$1"
  local canonical_count
  local state_doc

  canonical_count=$({ grep -F '.local/state/ship.loop.local.json' $SHIP_STATE_DOCS 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [ "$skill_file" != "$SHIP_SKILL" ]; then
    canonical_count=$({ grep -F '.local/state/ship.loop.local.json' "$skill_file" \
      "$STATE_FIELDS" "$LOCAL_REVIEW" "$CI_WATCH" "$MERGE_DOC" \
      "$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md" \
      "$ROOT_DIR/plugins/go-workflow/lib/ship/bot-watch.md" \
      "$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md" \
      "$ROOT_DIR/plugins/go-workflow/lib/ship/push-and-pr.md" 2>/dev/null || true; } | wc -l | tr -d ' ')
  fi
  [ "$canonical_count" -eq 1 ] || return 1
  grep -qF 'CANONICAL_STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/ship.loop.local.json"' "$skill_file" || return 1
  grep -qF 'LINKED_STATE_CANDIDATES=()' "$skill_file" || return 1
  grep -qF 'LEGACY_STATE_FILE="${LINKED_STATE_CANDIDATES[0]}"' "$skill_file" || return 1
  grep -qF 'STATE_FILE="$CANONICAL_STATE_FILE"' "$skill_file" || return 1
  grep -qF 'mv "$LEGACY_STATE_FILE" "$CANONICAL_STATE_FILE"' "$skill_file" || return 1
  grep -qF 'CALLER_LOOP_STATE_FILE' "$skill_file" || return 1
  grep -qF 'CALLER_WORKFLOW_STATE_PATH' "$skill_file" || return 1
  grep -qF 'WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "ship")' "$skill_file" || return 1
  grep -qF 'read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"' "$skill_file" || return 1
  grep -qF '"[\"SHIPPED\",\"INCOMPLETE\"]"' "$skill_file" || return 1
  grep -qF 'set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "shipped" "" "complete"' "$MERGE_DOC" || return 1
  for state_doc in $SHIP_STATE_DOCS; do
    if grep -Eq 'jq .*\.([a-z_]+).*("?\$STATE_FILE"?)|jq .*"?\$STATE_FILE"?.*\.([a-z_]+)' "$state_doc"; then
      return 1
    fi
  done
}

echo -n "Ship state contract uses one resolved file and path-aware access... "
if validate_ship_state_contract "$SHIP_SKILL"; then
  echo "OK"
else
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
fi

MUTATED_SHIP_SKILL=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-mutated-ship-skill-XXXXXX")
sed 's#\.local/state/ship\.loop\.local\.json#.local/state/ship-v2.loop.local.json#' \
  "$SHIP_SKILL" > "$MUTATED_SHIP_SKILL"
echo -n "Ship state contract assertion rejects a mutated standalone filename... "
if validate_ship_state_contract "$MUTATED_SHIP_SKILL"; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$MUTATED_SHIP_SKILL"

MUTATED_LEGACY_SHIP_SKILL=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-mutated-legacy-ship-skill-XXXXXX")
sed 's/mv "$LEGACY_STATE_FILE" "$CANONICAL_STATE_FILE"/:/' \
  "$SHIP_SKILL" > "$MUTATED_LEGACY_SHIP_SKILL"
echo -n "Ship state contract assertion rejects disabled linked-worktree migration... "
if validate_ship_state_contract "$MUTATED_LEGACY_SHIP_SKILL"; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$MUTATED_LEGACY_SHIP_SKILL"

SHIP_BOOTSTRAP_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-ship-bootstrap-XXXXXX")
awk '
  /^## 0\. State File Bootstrap$/ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$SHIP_SKILL" > "$SHIP_BOOTSTRAP_BLOCK"

SHIP_STATE_FIELDS_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-ship-state-fields-XXXXXX")
awk '
  /^## Step 1 Initial Persist$/ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$STATE_FIELDS" > "$SHIP_STATE_FIELDS_BLOCK"

FRESH_SHIP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-fresh-ship-XXXXXX")
FRESH_PLUGIN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-fresh-ship-plugin-XXXXXX")
FRESH_SHIP_ROOT=$(cd "$FRESH_SHIP_ROOT" && pwd -P)
FRESH_PLUGIN_ROOT=$(cd "$FRESH_PLUGIN_ROOT" && pwd -P)
git -C "$FRESH_SHIP_ROOT" init -q -b fixture
git -C "$FRESH_SHIP_ROOT" config user.name "Fresh Ship State Test"
git -C "$FRESH_SHIP_ROOT" config user.email "fresh-ship-state@example.com"
git -C "$FRESH_SHIP_ROOT" commit --allow-empty -qm "test: initialize fresh ship fixture"
mkdir -p "$FRESH_PLUGIN_ROOT/lib/ship" "$FRESH_PLUGIN_ROOT/scripts"
cp "$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh" "$FRESH_PLUGIN_ROOT/lib/loop-state.sh"
cp "$ROOT_DIR/plugins/go-workflow/scripts/setup-loop.sh" "$FRESH_PLUGIN_ROOT/scripts/setup-loop.sh"
cp "$RESUME_MESSAGES" "$FRESH_PLUGIN_ROOT/lib/ship/resume-messages.json"
chmod +x "$FRESH_PLUGIN_ROOT/scripts/setup-loop.sh"

set +e
FRESH_START_OUTPUT=$(cd "$FRESH_SHIP_ROOT" && \
  CLAUDE_PLUGIN_ROOT="$FRESH_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
    LLM_CHOICE=codex
    LLM_EXPLICIT=false
    NO_MERGE=false
    SKIP_COVERAGE=false
    COVERAGE_THRESHOLD=60
    GEMINI_TIER=""
    source "$2"
    set_loop_phase "$STATE_FILE" "ci-watch" "$WORKFLOW_STATE_PATH"
    set_loop_json_field "$STATE_FILE" "pass" 2 "$WORKFLOW_STATE_PATH"
    printf "STATE=%s\n" "$STATE_FILE"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" "$SHIP_STATE_FIELDS_BLOCK" 2>&1)
FRESH_START_STATUS=$?
set -e
FRESH_SHIP_STATE="$FRESH_SHIP_ROOT/.local/state/ship.loop.local.json"

if [ "$FRESH_START_STATUS" -ne 0 ] ||
   ! printf '%s\n' "$FRESH_START_OUTPUT" | grep -qF "STATE=$FRESH_SHIP_STATE" ||
   ! jq -e '
     .schema_version == 2 and
     .owner_workflow == "ship" and
     .phase == "ci-watch" and
     .pass == 2 and
     .original_repo_root == $root and
     .worktree_path == $root and
     .repo_slug == "example/project"
   ' --arg root "$FRESH_SHIP_ROOT" "$FRESH_SHIP_STATE" >/dev/null 2>&1; then
  fail "fresh standalone ship must initialize its canonical schema-v2 owner state"
fi

FRESH_STOP_OUTPUT=$(cd "$FRESH_SHIP_ROOT" && \
  printf '%s\n' '{"transcript_path":""}' | bash "$STOP_HOOK")
printf '%s\n' '#!/bin/bash' 'exit 97' > "$FRESH_PLUGIN_ROOT/scripts/setup-loop.sh"
chmod +x "$FRESH_PLUGIN_ROOT/scripts/setup-loop.sh"

set +e
FRESH_REENTRY_OUTPUT=$(cd "$FRESH_SHIP_ROOT" && \
  CLAUDE_PLUGIN_ROOT="$FRESH_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
    printf "STATE=%s\nPATH=%s\nEMBEDDED=%s\nPHASE=%s\nPASS=%s\n" \
      "$STATE_FILE" "$WORKFLOW_STATE_PATH" "$SHIP_EMBEDDED" "$PHASE" \
      "$(get_loop_field "$STATE_FILE" pass "$WORKFLOW_STATE_PATH")"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
FRESH_REENTRY_STATUS=$?
set -e

if ! printf '%s\n' "$FRESH_STOP_OUTPUT" | jq -e \
     '.decision == "block" and ((.reason // "") | length > 0)' >/dev/null 2>&1 ||
   [ "$FRESH_REENTRY_STATUS" -ne 0 ] ||
   ! printf '%s\n' "$FRESH_REENTRY_OUTPUT" | grep -qF "STATE=$FRESH_SHIP_STATE" ||
   ! printf '%s\n' "$FRESH_REENTRY_OUTPUT" | grep -qF 'PATH=[]' ||
   ! printf '%s\n' "$FRESH_REENTRY_OUTPUT" | grep -qF 'EMBEDDED=false' ||
   ! printf '%s\n' "$FRESH_REENTRY_OUTPUT" | grep -qF 'PHASE=ci-watch' ||
   ! printf '%s\n' "$FRESH_REENTRY_OUTPUT" | grep -qF 'PASS=2'; then
  fail "fresh standalone ship must re-enter its exact canonical state across a Stop boundary without a caller or setup"
fi

LEGACY_SHIP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-ship-XXXXXX")
LEGACY_PLUGIN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-ship-plugin-XXXXXX")
LEGACY_SHIP_TMP=$(cd "$LEGACY_SHIP_TMP" && pwd -P)
LEGACY_PLUGIN_ROOT=$(cd "$LEGACY_PLUGIN_ROOT" && pwd -P)
git -C "$LEGACY_SHIP_TMP" init -q -b fixture
git -C "$LEGACY_SHIP_TMP" config user.name "Ship State Test"
git -C "$LEGACY_SHIP_TMP" config user.email "ship-state@example.com"
git -C "$LEGACY_SHIP_TMP" commit --allow-empty -qm "test: initialize ship state fixture"
mkdir -p "$LEGACY_SHIP_TMP/.local/state" "$LEGACY_PLUGIN_ROOT/lib/ship" "$LEGACY_PLUGIN_ROOT/scripts"
cp "$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh" "$LEGACY_PLUGIN_ROOT/lib/loop-state.sh"
cp "$RESUME_MESSAGES" "$LEGACY_PLUGIN_ROOT/lib/ship/resume-messages.json"
printf '%s\n' '#!/bin/bash' 'exit 97' > "$LEGACY_PLUGIN_ROOT/scripts/setup-loop.sh"
chmod +x "$LEGACY_PLUGIN_ROOT/scripts/setup-loop.sh"
LEGACY_SHIP_STATE="$LEGACY_SHIP_TMP/.local/state/ship.loop.local.json"
jq -n \
  --arg original_repo_root "$LEGACY_SHIP_TMP" \
  --arg worktree_path "$LEGACY_SHIP_TMP" \
  '{loop_name:"ship",iteration:4,max_iterations:50,completion_promise:"SHIPPED",phase:"ci-watch",original_prompt:"ship",session_id:"",awaiting_driver_input:false,driver_input_reason:"",phase_messages:{"ci-watch":"Resume exact-head CI."},original_repo_root:$original_repo_root,worktree_path:$worktree_path,repo_slug:"example/project",pass:2,pr_number:"302",head_sha:"legacy-head"}' \
  > "$LEGACY_SHIP_STATE"

LEGACY_STOP_OUTPUT=$(cd "$LEGACY_SHIP_TMP" && \
  printf '%s\n' '{"transcript_path":""}' | bash "$STOP_HOOK")

if ! printf '%s\n' "$LEGACY_STOP_OUTPUT" | jq -e \
  '.decision == "block" and ((.reason // "") | length > 0)' >/dev/null 2>&1; then
  fail "legacy standalone ship must block with a non-empty re-entry reason"
fi
if ! jq -e '
  .schema_version == 2 and
  .iteration == 5 and
  .phase == "ci-watch" and
  .pass == 2 and
  .pr_number == "302" and
  .head_sha == "legacy-head" and
  (.terminal_promises | index("SHIPPED")) != null and
  (.terminal_promises | index("INCOMPLETE")) != null
' "$LEGACY_SHIP_STATE" >/dev/null 2>&1; then
  fail "legacy standalone ship state must migrate in place without losing routing fields"
fi

set +e
LEGACY_REENTRY_OUTPUT=$(cd "$LEGACY_SHIP_TMP" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
    printf "STATE=%s\nPATH=%s\nEMBEDDED=%s\nPHASE=%s\nPASS=%s\nPR=%s\nHEAD=%s\n" \
      "$STATE_FILE" "$WORKFLOW_STATE_PATH" "$SHIP_EMBEDDED" \
      "$(get_loop_field "$STATE_FILE" phase "$WORKFLOW_STATE_PATH")" \
      "$(get_loop_field "$STATE_FILE" pass "$WORKFLOW_STATE_PATH")" \
      "$(get_loop_field "$STATE_FILE" pr_number "$WORKFLOW_STATE_PATH")" \
      "$(get_loop_field "$STATE_FILE" head_sha "$WORKFLOW_STATE_PATH")"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_REENTRY_STATUS=$?
set -e

if [ "$LEGACY_REENTRY_STATUS" -ne 0 ] ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF "STATE=$LEGACY_SHIP_STATE" ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'PATH=[]' ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'EMBEDDED=false' ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'PHASE=ci-watch' ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'PASS=2' ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'PR=302' ||
   ! printf '%s\n' "$LEGACY_REENTRY_OUTPUT" | grep -qF 'HEAD=legacy-head'; then
  fail "standalone ship re-entry must resolve the canonical migrated file without setup"
fi
LEGACY_LOOP_COUNT=0
for legacy_loop_file in "$LEGACY_SHIP_TMP/.local/state"/*.loop.local.json; do
  [ -f "$legacy_loop_file" ] || continue
  LEGACY_LOOP_COUNT=$((LEGACY_LOOP_COUNT + 1))
done
if [ "$LEGACY_LOOP_COUNT" -ne 1 ]; then
  fail "standalone ship re-entry must not create a second loop state file"
fi

LEGACY_LINK_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-link-root-XXXXXX")
LEGACY_LINK_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-link-parent-XXXXXX")
LEGACY_LINK_ROOT=$(cd "$LEGACY_LINK_ROOT" && pwd -P)
LEGACY_LINK_WORKTREE="$LEGACY_LINK_PARENT/linked"
git -C "$LEGACY_LINK_ROOT" init -q -b main
git -C "$LEGACY_LINK_ROOT" config user.name "Ship Linked State Test"
git -C "$LEGACY_LINK_ROOT" config user.email "ship-linked-state@example.com"
git -C "$LEGACY_LINK_ROOT" commit --allow-empty -qm "test: initialize linked ship fixture"
git -C "$LEGACY_LINK_ROOT" worktree add -q -b legacy-linked "$LEGACY_LINK_WORKTREE"
LEGACY_LINK_WORKTREE=$(cd "$LEGACY_LINK_WORKTREE" && pwd -P)
LEGACY_LINK_STATE="$LEGACY_LINK_WORKTREE/.local/state/ship.loop.local.json"
LEGACY_LINK_CANONICAL="$LEGACY_LINK_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$LEGACY_LINK_STATE")"
jq -n \
  '{loop_name:"ship",iteration:7,max_iterations:50,completion_promise:"SHIPPED",phase:"ci-watch",original_prompt:"ship",session_id:"",awaiting_driver_input:false,driver_input_reason:"",phase_messages:{"ci-watch":"Resume linked-worktree CI."},pass:3,pr_number:"302",head_sha:"linked-legacy-head"}' \
  > "$LEGACY_LINK_STATE"

set +e
LEGACY_LINK_OUTPUT=$(cd "$LEGACY_LINK_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
    printf "STATE=%s\nPATH=%s\nEMBEDDED=%s\n" "$STATE_FILE" "$WORKFLOW_STATE_PATH" "$SHIP_EMBEDDED"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_LINK_STATUS=$?
set -e

if [ "$LEGACY_LINK_STATUS" -ne 0 ] ||
   [ -e "$LEGACY_LINK_STATE" ] ||
   [ ! -f "$LEGACY_LINK_CANONICAL" ] ||
   ! printf '%s\n' "$LEGACY_LINK_OUTPUT" | grep -qF "STATE=$LEGACY_LINK_CANONICAL" ||
   ! jq -e \
     --arg original_repo_root "$LEGACY_LINK_ROOT" \
     --arg worktree_path "$LEGACY_LINK_WORKTREE" '
       .schema_version == 2 and
       .owner_workflow == "ship" and
       .phase == "ci-watch" and
       .pass == 3 and
       .pr_number == "302" and
       .head_sha == "linked-legacy-head" and
       .original_repo_root == $original_repo_root and
       .worktree_path == $worktree_path and
       .repo_slug == "example/project" and
       (.terminal_promises | index("SHIPPED")) != null and
       (.terminal_promises | index("INCOMPLETE")) != null
     ' "$LEGACY_LINK_CANONICAL" >/dev/null 2>&1; then
  fail "single released-shape linked-worktree ship state must relocate and resume from the canonical path"
fi

LEGACY_COLLISION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-collision-root-XXXXXX")
LEGACY_COLLISION_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-collision-parent-XXXXXX")
LEGACY_COLLISION_ROOT=$(cd "$LEGACY_COLLISION_ROOT" && pwd -P)
LEGACY_COLLISION_WORKTREE="$LEGACY_COLLISION_PARENT/linked"
git -C "$LEGACY_COLLISION_ROOT" init -q -b main
git -C "$LEGACY_COLLISION_ROOT" config user.name "Ship Collision Test"
git -C "$LEGACY_COLLISION_ROOT" config user.email "ship-collision@example.com"
git -C "$LEGACY_COLLISION_ROOT" commit --allow-empty -qm "test: initialize collision fixture"
git -C "$LEGACY_COLLISION_ROOT" worktree add -q -b collision-linked "$LEGACY_COLLISION_WORKTREE"
LEGACY_COLLISION_WORKTREE=$(cd "$LEGACY_COLLISION_WORKTREE" && pwd -P)
LEGACY_COLLISION_STATE="$LEGACY_COLLISION_WORKTREE/.local/state/ship.loop.local.json"
LEGACY_COLLISION_CANONICAL="$LEGACY_COLLISION_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$LEGACY_COLLISION_STATE")" "$(dirname "$LEGACY_COLLISION_CANONICAL")"
printf '%s\n' '{"loop_name":"ship","iteration":2,"completion_promise":"SHIPPED","phase":"pushing"}' > "$LEGACY_COLLISION_STATE"
jq -n \
  --arg original_repo_root "$LEGACY_COLLISION_ROOT" \
  --arg worktree_path "$LEGACY_COLLISION_WORKTREE" \
  '{schema_version:2,owner_workflow:"ship",loop_name:"ship",iteration:4,max_iterations:50,completion_promise:"SHIPPED",terminal_promises:["SHIPPED","INCOMPLETE"],components:{},phase:"ci-watch",original_prompt:"ship",session_id:"",original_repo_root:$original_repo_root,worktree_path:$worktree_path,repo_slug:"example/project"}' \
  > "$LEGACY_COLLISION_CANONICAL"
cp "$LEGACY_COLLISION_STATE" "$LEGACY_COLLISION_STATE.before"
cp "$LEGACY_COLLISION_CANONICAL" "$LEGACY_COLLISION_CANONICAL.before"

set +e
LEGACY_COLLISION_OUTPUT=$(cd "$LEGACY_COLLISION_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
    printf "STATE=%s\n" "$STATE_FILE"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_COLLISION_STATUS=$?
set -e

if [ "$LEGACY_COLLISION_STATUS" -ne 0 ] ||
   ! printf '%s\n' "$LEGACY_COLLISION_OUTPUT" | grep -qF "STATE=$LEGACY_COLLISION_CANONICAL" ||
   ! cmp -s "$LEGACY_COLLISION_STATE" "$LEGACY_COLLISION_STATE.before" ||
   ! cmp -s "$LEGACY_COLLISION_CANONICAL" "$LEGACY_COLLISION_CANONICAL.before"; then
  fail "canonical ship state must win over a linked-worktree stray without mutating either file"
fi

LEGACY_INVALID_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-invalid-root-XXXXXX")
LEGACY_INVALID_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-legacy-invalid-parent-XXXXXX")
LEGACY_INVALID_ROOT=$(cd "$LEGACY_INVALID_ROOT" && pwd -P)
LEGACY_INVALID_WORKTREE="$LEGACY_INVALID_PARENT/linked"
git -C "$LEGACY_INVALID_ROOT" init -q -b main
git -C "$LEGACY_INVALID_ROOT" config user.name "Ship Invalid State Test"
git -C "$LEGACY_INVALID_ROOT" config user.email "ship-invalid-state@example.com"
git -C "$LEGACY_INVALID_ROOT" commit --allow-empty -qm "test: initialize invalid state fixture"
git -C "$LEGACY_INVALID_ROOT" worktree add -q -b invalid-linked "$LEGACY_INVALID_WORKTREE"
LEGACY_INVALID_WORKTREE=$(cd "$LEGACY_INVALID_WORKTREE" && pwd -P)
LEGACY_INVALID_STATE="$LEGACY_INVALID_WORKTREE/.local/state/ship.loop.local.json"
LEGACY_INVALID_CANONICAL="$LEGACY_INVALID_ROOT/.local/state/ship.loop.local.json"
mkdir -p "$(dirname "$LEGACY_INVALID_STATE")"
LEGACY_MULTIPLE_STRAY="$LEGACY_INVALID_WORKTREE/.local/state/direct-smoke.loop.local.json"
printf '%s\n' '{"loop_name":"ship","iteration":2,"completion_promise":"SHIPPED","phase":"pushing"}' > "$LEGACY_INVALID_STATE"
printf '%s\n' '{"loop_name":"direct-smoke","iteration":1,"completion_promise":"DONE","phase":"testing"}' > "$LEGACY_MULTIPLE_STRAY"
LEGACY_MULTIPLE_OWNER_BEFORE=$(cksum "$LEGACY_INVALID_STATE")
LEGACY_MULTIPLE_STRAY_BEFORE=$(cksum "$LEGACY_MULTIPLE_STRAY")

set +e
LEGACY_MULTIPLE_OUTPUT=$(cd "$LEGACY_INVALID_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_MULTIPLE_STATUS=$?
set -e

echo -n "Ambiguous-state assertion rejects a diagnostic missing one candidate... "
LEGACY_MULTIPLE_MUTATION="ERROR: Ambiguous linked-worktree loop state candidates: $LEGACY_INVALID_STATE"
if ambiguous_output_names_files "$LEGACY_MULTIPLE_MUTATION" "$LEGACY_INVALID_STATE" "$LEGACY_MULTIPLE_STRAY"; then
  echo "FAIL"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

if [ "$LEGACY_MULTIPLE_STATUS" -eq 0 ] ||
   ! ambiguous_output_names_files "$LEGACY_MULTIPLE_OUTPUT" "$LEGACY_INVALID_STATE" "$LEGACY_MULTIPLE_STRAY" ||
   [ "$LEGACY_MULTIPLE_OWNER_BEFORE" != "$(cksum "$LEGACY_INVALID_STATE")" ] ||
   [ "$LEGACY_MULTIPLE_STRAY_BEFORE" != "$(cksum "$LEGACY_MULTIPLE_STRAY")" ] ||
   [ -e "$LEGACY_INVALID_CANONICAL" ]; then
  fail "multiple linked-worktree migration candidates must fail closed and name every unchanged file"
fi

rm -f "$LEGACY_MULTIPLE_STRAY"
printf '%s\n' '{invalid-json' > "$LEGACY_INVALID_STATE"
cp "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before"
LEGACY_INVALID_EXPECTED="ERROR: Invalid linked-worktree legacy ship state '$LEGACY_INVALID_STATE': expected released unversioned ship JSON with a SHIPPED or INCOMPLETE promise; refusing migration to '$LEGACY_INVALID_CANONICAL'."

set +e
LEGACY_INVALID_OUTPUT=$(cd "$LEGACY_INVALID_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_INVALID_STATUS=$?
set -e

if [ "$LEGACY_INVALID_STATUS" -eq 0 ] ||
   ! printf '%s\n' "$LEGACY_INVALID_OUTPUT" | grep -qF "$LEGACY_INVALID_EXPECTED" ||
   ! cmp -s "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before" ||
   [ -e "$LEGACY_INVALID_CANONICAL" ]; then
  fail "invalid linked-worktree ship state must fail clearly without mutation"
fi

printf '%s\n' '{"loop_name":"address-review-302","iteration":2,"completion_promise":"COMPLETE","phase":"watching"}' > "$LEGACY_INVALID_STATE"
cp "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before"
set +e
LEGACY_FOREIGN_OUTPUT=$(cd "$LEGACY_INVALID_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_FOREIGN_STATUS=$?
set -e

if [ "$LEGACY_FOREIGN_STATUS" -eq 0 ] ||
   ! printf '%s\n' "$LEGACY_FOREIGN_OUTPUT" | grep -qF "$LEGACY_INVALID_EXPECTED" ||
   ! cmp -s "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before" ||
   [ -e "$LEGACY_INVALID_CANONICAL" ]; then
  fail "foreign linked-worktree loop state must fail clearly without mutation"
fi

printf '%s\n' '{"loop_name":"ship","iteration":2,"completion_promise":"COMPLETE","phase":"watching"}' > "$LEGACY_INVALID_STATE"
cp "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before"
set +e
LEGACY_FOREIGN_PROMISE_OUTPUT=$(cd "$LEGACY_INVALID_WORKTREE" && \
  CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" CALLER_LOOP_STATE_FILE="" CALLER_WORKFLOW_STATE_PATH="" ARGUMENTS="" \
  bash -c '
    gh() { printf "%s\n" "example/project"; }
    source "$1"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" 2>&1)
LEGACY_FOREIGN_PROMISE_STATUS=$?
set -e

if [ "$LEGACY_FOREIGN_PROMISE_STATUS" -eq 0 ] ||
   ! printf '%s\n' "$LEGACY_FOREIGN_PROMISE_OUTPUT" | grep -qF "$LEGACY_INVALID_EXPECTED" ||
   ! cmp -s "$LEGACY_INVALID_STATE" "$LEGACY_INVALID_STATE.before" ||
   [ -e "$LEGACY_INVALID_CANONICAL" ]; then
  fail "foreign linked-worktree terminal promise must fail clearly without mutation"
fi

rm -rf "$LEGACY_LINK_ROOT" "$LEGACY_LINK_PARENT" \
  "$LEGACY_COLLISION_ROOT" "$LEGACY_COLLISION_PARENT" \
  "$LEGACY_INVALID_ROOT" "$LEGACY_INVALID_PARENT"

SHIP_RESULT_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-ship-result-XXXXXX")
SHIP_FAILURE_BLOCK=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-ship-failure-XXXXXX")
awk '
  /^## 13g\. Return result$/ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$MERGE_DOC" > "$SHIP_RESULT_BLOCK"
awk '
  /^## Hard Invariant Failure$/ { section=1 }
  section && /^```bash$/ { block=1; next }
  block && /^```$/ { exit }
  block { print }
' "$SHIP_SKILL" > "$SHIP_FAILURE_BLOCK"

EMBEDDED_SHIP_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-embedded-ship-XXXXXX")
EMBEDDED_STATE="$EMBEDDED_SHIP_TMP/.local/state/complete-issue-302.loop.local.json"
mkdir -p "$(dirname "$EMBEDDED_STATE")"
jq -n \
  '{schema_version:2,owner_workflow:"complete-issue",loop_name:"complete-issue-302",iteration:3,max_iterations:100,completion_promise:"COMPLETE",terminal_promises:["COMPLETE","INCOMPLETE"],phase:"verifying",components:{e2e_verify:{phase:"shipping",result:"",reason:"",components:{}}}}' \
  > "$EMBEDDED_STATE"

set +e
EMBEDDED_OUTPUT=$(CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" \
  CALLER_LOOP_STATE_FILE="$EMBEDDED_STATE" \
  CALLER_WORKFLOW_STATE_PATH='["components","e2e_verify"]' \
  ARGUMENTS="" \
  bash -c '
    source "$1"
    source "$2"
    jq -c "{root_phase:.phase,root_promise:.completion_promise,ship:.components.e2e_verify.components.ship}" "$STATE_FILE"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" "$SHIP_RESULT_BLOCK" 2>&1)
EMBEDDED_STATUS=$?
set -e

if [ "$EMBEDDED_STATUS" -ne 0 ] ||
   printf '%s\n' "$EMBEDDED_OUTPUT" | grep -qF '<done>SHIPPED</done>' ||
   ! printf '%s\n' "$EMBEDDED_OUTPUT" | tail -1 | jq -e '
     .root_phase == "verifying" and
     .root_promise == "COMPLETE" and
     .ship.phase == "complete" and
     .ship.result == "shipped" and
     .ship.reason == ""
   ' >/dev/null 2>&1; then
  fail "embedded ship must return a structured result without changing caller terminal state"
fi
if [ -e "$EMBEDDED_SHIP_TMP/.local/state/ship.loop.local.json" ]; then
  fail "embedded ship must not create standalone ship state"
fi

EMBEDDED_FAILURE_STATE="$EMBEDDED_SHIP_TMP/.local/state/complete-issue-303.loop.local.json"
jq -n \
  '{schema_version:2,owner_workflow:"complete-issue",loop_name:"complete-issue-303",iteration:3,max_iterations:100,completion_promise:"COMPLETE",terminal_promises:["COMPLETE","INCOMPLETE"],phase:"verifying",components:{e2e_verify:{phase:"shipping",result:"",reason:"",components:{}}}}' \
  > "$EMBEDDED_FAILURE_STATE"
set +e
EMBEDDED_FAILURE_OUTPUT=$(CLAUDE_PLUGIN_ROOT="$LEGACY_PLUGIN_ROOT" \
  CALLER_LOOP_STATE_FILE="$EMBEDDED_FAILURE_STATE" \
  CALLER_WORKFLOW_STATE_PATH='["components","e2e_verify"]' \
  WORKFLOW_REASON="fixture-ship-failure" \
  ARGUMENTS="" \
  bash -c '
    source "$1"
    source "$2"
    jq -c "{root_phase:.phase,root_promise:.completion_promise,ship:.components.e2e_verify.components.ship}" "$STATE_FILE"
  ' _ "$SHIP_BOOTSTRAP_BLOCK" "$SHIP_FAILURE_BLOCK" 2>&1)
EMBEDDED_FAILURE_STATUS=$?
set -e

if [ "$EMBEDDED_FAILURE_STATUS" -ne 0 ] ||
   printf '%s\n' "$EMBEDDED_FAILURE_OUTPUT" | grep -qF '<done>' ||
   ! printf '%s\n' "$EMBEDDED_FAILURE_OUTPUT" | tail -1 | jq -e '
     .root_phase == "verifying" and
     .root_promise == "COMPLETE" and
     .ship.phase == "incomplete" and
     .ship.result == "incomplete" and
     .ship.reason == "fixture-ship-failure"
   ' >/dev/null 2>&1; then
  fail "embedded ship failure must return a non-empty structured reason without a marker"
fi

rm -f "$SHIP_BOOTSTRAP_BLOCK" "$SHIP_RESULT_BLOCK" "$SHIP_FAILURE_BLOCK"
rm -rf "$LEGACY_SHIP_TMP" "$LEGACY_PLUGIN_ROOT" "$EMBEDDED_SHIP_TMP"

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS ship E2E gate issue(s)"
  exit 1
fi

echo "All ship E2E gate tests passed."
