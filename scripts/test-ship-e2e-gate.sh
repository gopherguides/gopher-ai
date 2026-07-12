#!/bin/bash
# Verify $ship treats missing UI E2E prerequisites as a blocking condition.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCAL_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
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

  if ! grep -qE "$pattern" "$file"; then
    fail "$label"
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE "$pattern" "$file"; then
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

require_text "$MERGE_DOC" "e2e_result.*blocked" \
  "ship merge phase must read blocked E2E state"
require_text "$MERGE_DOC" "E2E PREREQUISITE MISSING" \
  "ship merge phase must stop on blocked E2E state"
require_text "$MERGE_DOC" "Verification partial" \
  "ship summary must avoid unqualified verification-complete wording for partial E2E"

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
require_text "$LOCAL_REVIEW" "run_in_background=false" \
  "ship agent reviews must run synchronously"
require_text "$LOCAL_REVIEW" 'review_result="skipped"' \
  "ship must record headless agent review skips"
require_text "$RESUME_MESSAGES" "Do not start another review.*Commit the validated staged diff.*push every local commit.*non-draft PR" \
  "ship reviewing resume message must drive commit, push, and PR creation"
require_text "$COMPLETE_ISSUE" '`reviewing` → Phase 3' \
  "complete-issue must not resume an expired agent review"

HEADLESS_TMP=$(mktemp -d /tmp/ship-headless-e2e-XXXXXX)
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
