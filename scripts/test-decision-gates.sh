#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DECISIONS="$ROOT_DIR/plugins/go-workflow/lib/decision-gates.md"
START="$ROOT_DIR/plugins/go-workflow/skills/start-issue/SKILL.md"
START_FLOW="$ROOT_DIR/plugins/go-workflow/lib/start-issue/orchestrated-workflow.md"
START_MANUAL="$ROOT_DIR/plugins/go-workflow/lib/start-issue/manual-workflow.md"
START_WORKTREE="$ROOT_DIR/plugins/go-workflow/lib/start-issue/worktree-create.md"
CREATE_PR="$ROOT_DIR/plugins/go-workflow/skills/create-pr/SKILL.md"
REVIEW_PLAN="$ROOT_DIR/plugins/go-workflow/lib/review-planning.md"
SHIP="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
SHIP_PREREQUISITES="$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md"
SHIP_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
SHIP_BOTS="$ROOT_DIR/plugins/go-workflow/lib/ship/bot-watch.md"
ADDRESS="$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md"
ADDRESS_FIX="$ROOT_DIR/plugins/go-workflow/skills/address-review/fix-cycle.md"
ADDRESS_WATCH="$ROOT_DIR/plugins/go-workflow/skills/address-review/watch-loop.md"
COMPLETE="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
COMPLETE_FALLBACK="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/codex-fallback.md"
E2E="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
TMUX="$ROOT_DIR/plugins/go-workflow/skills/tmux-start/SKILL.md"
WORKTREE="$ROOT_DIR/plugins/go-workflow/skills/worktree/SKILL.md"
WORKTREE_CREATE="$ROOT_DIR/plugins/go-workflow/skills/worktree/create.md"
WORKTREE_REMOVE="$ROOT_DIR/plugins/go-workflow/skills/worktree/remove.md"
WORKTREE_PRUNE="$ROOT_DIR/plugins/go-workflow/skills/worktree/prune.md"
REVIEW_DEEP="$ROOT_DIR/plugins/go-workflow/skills/review-deep/SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

section_text() {
  local file="$1"
  local start="$2"
  local end="$3"
  awk -v start="$start" -v end="$end" '
    index($0, start) { active = 1 }
    active && index($0, end) && !index($0, start) { exit }
    active { print }
  ' "$file" | tr '\n' ' '
}

file_text() {
  tr '\n' ' ' < "$1"
}

assert_contains() {
  local text="$1"
  local needle="$2"
  local label="$3"
  [[ "$text" == *"$needle"* ]] || fail "$label"
}

assert_not_contains() {
  local text="$1"
  local needle="$2"
  local label="$3"
  [[ "$text" != *"$needle"* ]] || fail "$label"
}

echo "=== Decision Gate Behavior Tests ==="

driver_contract=$(section_text "$DECISIONS" "## Driver-resolvable gate" "## Missing-intent gate")
assert_contains "$driver_contract" "repository state" "driver contract lacks repository evidence"
assert_contains "$driver_contract" "Decision:" "driver contract lacks a decision record"
assert_contains "$driver_contract" "Evidence:" "driver contract lacks an evidence record"
assert_contains "$driver_contract" "Rationale:" "driver contract lacks a rationale record"
assert_contains "$driver_contract" "Continue after stating the rationale" "driver contract does not continue"

intent_contract=$(section_text "$DECISIONS" "## Missing-intent gate" "## Hard invariant")
for family in \
  "missing issue, pull request, worktree, or action target" \
  "copy environment files or secrets" \
  "issue semantics" \
  "product behavior or acceptance criteria" \
  "explicitly selected review backend" \
  "equally valid worktrees" \
  "optional branch deletion"; do
  assert_contains "$intent_contract" "$family" "missing-intent taxonomy omits $family"
done
assert_contains "$intent_contract" "native structured-input" "missing intent does not use native structured input"
assert_contains "$intent_contract" "ask one concise question in the final" "missing intent lacks final-response recovery"
assert_contains "$intent_contract" "Do not perform the dependent action" "missing intent can continue"
assert_contains "$intent_contract" "completion marker" "missing intent can claim completion"

start_worktree=$(section_text "$START" "## Worktree Detection & Decision" "## If the driver selected")
assert_contains "$start_worktree" "provides isolation" "worktree placement ignores isolation evidence"
assert_contains "$start_worktree" "clean non-default" "worktree placement ignores branch evidence"
assert_contains "$start_worktree" "Do not request input" "worktree placement still defers a technical choice"

duplicate_gate=$(section_text "$START_FLOW" "## Step 1:" "## Step 2:")
assert_contains "$duplicate_gate" "stop duplicate implementation" "duplicate gate cannot stop redundant work"
assert_contains "$duplicate_gate" "overlap is partial" "duplicate gate cannot preserve distinct scope"
assert_contains "$duplicate_gate" "Rationale" "duplicate gate lacks rationale"
assert_contains "$duplicate_gate" "completion promise" "terminal duplicate does not update durable state"
assert_contains "$duplicate_gate" "<done>INCOMPLETE</done>" "terminal duplicate can claim completion"

template_gate=$(section_text "$CREATE_PR" "### Step 4:" "### Step 5:")
assert_contains "$template_gate" "template whose name and required" "template gate ignores template evidence"
assert_contains "$template_gate" "first lexical template" "template gate lacks deterministic tie-break"
assert_contains "$template_gate" "do not request input" "template gate still defers a technical choice"

pr_submission=$(section_text "$CREATE_PR" "### Step 8:" "### Step 9:")
assert_contains "$pr_submission" "gh pr view" "create-pr does not detect an existing pull request"
assert_contains "$pr_submission" "headRefName" "create-pr does not verify the existing pull request head"
assert_contains "$pr_submission" "baseRefName" "create-pr does not verify the existing pull request base"
assert_contains "$pr_submission" "if [ -n \"\$EXISTING_PR\" ]" "create-pr does not branch on an existing pull request"
assert_contains "$pr_submission" "Reusing pull request" "create-pr does not report a reused pull request"
assert_contains "$pr_submission" "WORKFLOW_REASON=existing-pr-mismatch" "create-pr can reuse a mismatched pull request"
assert_contains "$pr_submission" "else" "create-pr lacks a new pull request path"
assert_contains "$pr_submission" "gh pr create" "create-pr no longer creates a pull request when none exists"

review_capacity=$(section_text "$REVIEW_PLAN" "Follow the displayed plan" "__END__")
assert_contains "$review_capacity" "further partitioning" "review planning cannot recover from capacity limits"
assert_contains "$review_capacity" "higher-capacity backend" "review planning cannot use backend evidence"
assert_contains "$review_capacity" "explicitly selected backend" "review planning can override explicit backend intent"
assert_contains "$review_capacity" "baseline coverage cannot be narrowed" "review planning can waive coverage"

review_runtime=$(file_text "$REVIEW_PLAN")
assert_contains "$review_runtime" "REVIEW_PLAN=\$(/bin/bash \"<PLUGIN_ROOT>/scripts/review-plan.sh\"" "review planner does not use /bin/bash at runtime"
assert_not_contains "$review_runtime" "REVIEW_PLAN=\$(\"<PLUGIN_ROOT>/scripts/review-plan.sh\"" "review planner still executes directly at runtime"

dirty_ship=$(section_text "$SHIP" "## 3. Detect Context" "## 4. Prerequisite Check")
assert_contains "$dirty_ship" "unambiguously in scope" "dirty ship cannot identify owned changes"
assert_contains "$dirty_ship" "Preserve unrelated changes" "dirty ship can capture unrelated changes"
assert_contains "$dirty_ship" "WORKFLOW_REASON=unowned-worktree-changes" "ambiguous ship ownership has no incomplete outcome"
assert_not_contains "$dirty_ship" "Commit them before shipping, or abort?" "dirty ship still uses an option menu"

timeout_recovery=$(section_text "$SHIP_REVIEW" "#### Exit code 124" "#### Other non-zero exit codes")
assert_contains "$timeout_recovery" "Retry once" "review timeout lacks bounded retry"
assert_contains "$timeout_recovery" 'without `--output-schema`' "review timeout lacks schema recovery"
assert_contains "$timeout_recovery" "remaining passes" "quick-mode recovery ignores coverage"
assert_contains "$timeout_recovery" "explicitly selected backend" "review timeout can override explicit backend intent"

bot_discovery=$(section_text "$SHIP_BOTS" "## No bots detected yet" "## Persist discovered bots")
assert_contains "$bot_discovery" "at least 2 minutes old" "bot discovery does not honor startup window"
assert_contains "$bot_discovery" "3 additional times" "bot discovery lacks bounded observation"
assert_contains "$bot_discovery" "proceed to Step 13" "bot discovery lacks terminal recovery"
assert_contains "$bot_discovery" "Do not request input" "bot discovery still defers bounded waiting"

bot_timeout=$(section_text "$ADDRESS_WATCH" "### 12b." "### 12c.")
assert_contains "$bot_timeout" "go to 12d" "bot timeout does not re-trigger from registry evidence"
assert_contains "$bot_timeout" "bot-approval-timeout" "untriggerable bot timeout lacks incomplete reason"
assert_not_contains "$bot_timeout" "keep waiting" "bot timeout still presents an unbounded wait menu"

bot_exhaustion=$(section_text "$ADDRESS_WATCH" "### 12d." "__END__")
assert_contains "$bot_exhaustion" "third unsuccessful re-review trigger" "bot re-trigger lacks a bounded limit"
assert_contains "$bot_exhaustion" "bot-approval-exhausted" "bot exhaustion lacks incomplete reason"
assert_contains "$bot_exhaustion" "**Incomplete Approval Outcome**" "bot exhaustion can claim completion"

bot_success=$(section_text "$ADDRESS_WATCH" "### 12a." "### 12b.")
assert_contains "$bot_success" "return control to ship Step 13" "nested bot watch can terminate ship early"
assert_contains "$bot_success" "standalone address-review" "standalone bot watch lacks its completion outcome"
assert_contains "$bot_success" "top-level completion criteria" "caller completion criteria are not authoritative"

bot_baseline=$(section_text "$ADDRESS_WATCH" "**CRITICAL: Persist the baseline" "## Incomplete Approval Outcome")
assert_contains "$bot_baseline" '${BOT_REVIEW_BASELINE:-}' "clean review watch fallback is not nounset-safe"

dirty_review=$(section_text "$ADDRESS_FIX" "### Protect Pre-existing Target Changes" "### Parallel Fix Dispatch")
assert_contains "$dirty_review" "pre-existing diff" "review ownership gate does not inspect evidence"
assert_contains "$dirty_review" "do not edit or stage" "review ownership gate can capture unrelated hunks"
assert_contains "$dirty_review" "WORKFLOW_REASON=unowned-review-target-changes" "review ownership gate lacks incomplete outcome"

clean_review=$(section_text "$ADDRESS_FIX" "### If no feedback found:" "### If only pending reviews")
assert_contains "$clean_review" "REVIEW_CLEAN=true" "clean review does not return structured runtime state"
assert_contains "$clean_review" 'REVIEW_STATE_FILE="${STATE_FILE:-${LOOP_STATE_FILE:-$ORIGINAL_REPO_ROOT/' "clean review does not prefer caller-owned state"
assert_contains "$clean_review" 'set_loop_field "$REVIEW_STATE_FILE" "review_clean" "true"' "clean review does not persist durable state"
assert_contains "$clean_review" "Skip Steps 4, 4.5, 6, 8, 9, and 10" "clean review does not skip inapplicable mutation work"
assert_contains "$clean_review" "Step 5" "clean review skips local verification"
assert_contains "$clean_review" "Step 7" "clean review skips CI verification"
assert_contains "$clean_review" "Step 11" "clean review skips completion verification"
assert_contains "$clean_review" "After Step 11 succeeds" "clean review can transition before completion verification"
assert_contains "$clean_review" '[ "${EMBEDDED_WORKFLOW:-false}" != "true" ]' "embedded clean review can mutate its caller phase"
assert_contains "$clean_review" '[ "${CURRENT_PHASE:-}" = "fixing" ]' "clean review transition ignores the current phase"
assert_contains "$clean_review" '[ "${WATCH_MODE:-false}" = "true" ]' "clean review transition ignores watch mode"
assert_contains "$clean_review" '[ -n "${DETECTED_BOTS:-}" ]' "clean review transition ignores detected bots"
assert_not_contains "$clean_review" "<done>COMPLETE</done>" "clean review can terminate before completion gates"

clean_review_ci=$(section_text "$ADDRESS_FIX" "## Step 7: Watch CI" "## Step 8: Reply")
assert_contains "$clean_review_ci" 'CI_PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM")' "clean review CI does not refresh PR metadata"
assert_contains "$clean_review_ci" 'PR_HEAD_SHA=$(jq -er '\''.head.sha'\'' <<< "$CI_PR_JSON")' "clean review CI can consume an undefined PR head"
assert_contains "$clean_review_ci" 'github_watch_pr_checks "$PR_NUM" "$PR_HEAD_SHA"' "clean review CI is not pinned to the refreshed PR head"

embedded_review=$(section_text "$ADDRESS" "## Embedded Consumer Contract" "## Completion Criteria")
assert_contains "$embedded_review" "Steps 2-11" "embedded address-review contract lacks its execution boundary"
assert_contains "$embedded_review" "REVIEW_CLEAN" "embedded address-review contract lacks structured runtime state"
assert_contains "$embedded_review" "review_clean" "embedded address-review contract lacks durable state"
assert_contains "$embedded_review" "return control to the caller" "embedded address-review can retain workflow control"
assert_contains "$embedded_review" "no terminal marker" "embedded address-review can terminate its caller"
assert_not_contains "$embedded_review" "<done>COMPLETE</done>" "embedded address-review owns a foreign completion marker"

embedded_invariant=$(section_text "$ADDRESS" "## Hard Invariant Failure" "## Context & Bot Discovery")
assert_contains "$embedded_invariant" 'INVARIANT_STATE_FILE="${STATE_FILE:-${LOOP_STATE_FILE:-}}"' "embedded invariant cannot use caller-owned state"
assert_contains "$embedded_invariant" "returns the structured incomplete state" "embedded invariant lacks a structured return"
assert_contains "$embedded_invariant" "emits no terminal marker" "embedded invariant owns its caller's terminal marker"

address_completion=$(section_text "$ADDRESS" "## Completion Criteria" "## Supporting Files")
assert_contains "$address_completion" "standalone address-review owns" "standalone address-review does not own its final marker"
assert_contains "$address_completion" "after Step 11" "standalone address-review can terminate before completion verification"

address_step_11=$(section_text "$ADDRESS" "## Step 11: Verify Completion" "## Step 12: Watch")
assert_contains "$address_step_11" 'REVIEW_HEAD_EXPECTATION="${EXPECTED_REVIEW_HEAD:-$(git -C "$WORKTREE_PATH" rev-parse HEAD)}"' "embedded completion cannot bind Step 11 to the caller head"
assert_contains "$address_step_11" '[ "$PR_HEAD_SHA" != "$REVIEW_HEAD_EXPECTATION" ]' "embedded completion accepts a concurrent PR head shift"

post_review=$(section_text "$REVIEW_DEEP" "### Post to PR" "## Further Reading")
assert_contains "$post_review" "original request explicitly asks" "review posting ignores request evidence"
assert_contains "$post_review" "otherwise keep the report" "review posting lacks deterministic default"
assert_contains "$post_review" "Do not request input" "review posting still presents an option menu"

safe_remove=$(section_text "$WORKTREE_REMOVE" "### Step 4:" "### Step 5:")
assert_contains "$safe_remove" "original removal request as authorization" "safe removal asks for redundant consent"
assert_contains "$safe_remove" "closed issue, merged" "safe removal lacks safety evidence"
assert_contains "$safe_remove" "remove it without a redundant confirmation" "safe removal does not continue"

prune_scope=$(section_text "$WORKTREE_PRUNE" "### Step 4:" "### Step 5:")
assert_contains "$prune_scope" "prune request authorizes removal" "prune does not honor original request"
assert_contains "$prune_scope" "branch-cleanup" "prune does not separate optional branch intent"
assert_contains "$prune_scope" "stop before any removal" "prune missing intent can partially mutate"

for target_file in "$START" "$ADDRESS" "$COMPLETE" "$E2E" "$TMUX" "$WORKTREE" "$WORKTREE_CREATE"; do
  target_text=$(file_text "$target_file")
  assert_contains "$target_text" "missing-intent gate" "missing target protocol absent from ${target_file#"$ROOT_DIR"/}"
  assert_contains "$target_text" "stop before" "missing target can continue in ${target_file#"$ROOT_DIR"/}"
done

for secret_file in "$START_WORKTREE" "$WORKTREE_CREATE" "$TMUX"; do
  secret_text=$(file_text "$secret_file")
  assert_contains "$secret_text" "may contain secrets" "secret evidence absent from ${secret_file#"$ROOT_DIR"/}"
  assert_contains "$secret_text" "explicit" "secret copy can infer consent in ${secret_file#"$ROOT_DIR"/}"
  assert_contains "$secret_text" "stop before" "secret copy can continue in ${secret_file#"$ROOT_DIR"/}"
done

issue_type=$(section_text "$START" "## Step 1: Detect Issue Type" "## Implementation Workflow")
assert_contains "$issue_type" "labels, title, body, comments" "issue classification does not exhaust evidence"
assert_contains "$issue_type" "stop before" "ambiguous issue classification can continue"

product_intent=$(section_text "$START_FLOW" "## Step 4:" "## Step 5:")
assert_contains "$product_intent" "materially different product behavior" "design gate does not distinguish product intent"
assert_contains "$product_intent" "stop before implementation" "missing product intent can continue"
assert_contains "$(file_text "$START_MANUAL")" "missing-intent gate" "manual workflow lacks missing product intent recovery"

backend_gate=$(file_text "$SHIP_PREREQUISITES")
assert_contains "$backend_gate" "LLM_EXPLICIT=true" "ship does not preserve explicit backend intent"
assert_contains "$backend_gate" "LLM_EXPLICIT=false" "ship cannot resolve an unpinned backend"
assert_contains "$backend_gate" "review-backend-unavailable" "ship lacks no-backend incomplete outcome"
assert_contains "$(file_text "$COMPLETE_FALLBACK")" "Never continue to Phase 3 without" "complete-issue can bypass review after fallback failure"

terminal_review=$(section_text "$COMPLETE_FALLBACK" "## Terminal Review Failure" "## Codex NOT Available")
assert_contains "$terminal_review" 'set_loop_terminal_result' "complete-issue fallback does not persist a terminal result atomically"
assert_contains "$terminal_review" '"incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"' "complete-issue fallback lacks the complete terminal state transition"
assert_contains "$terminal_review" "<done>INCOMPLETE</done>" "complete-issue fallback lacks a terminal marker"

complete_routing=$(section_text "$COMPLETE" "Phase → step routing:" "---")
assert_contains "$complete_routing" '`incomplete`' "complete-issue lacks terminal re-entry routing"
assert_contains "$complete_routing" "stop without entering Phase 3" "complete-issue terminal re-entry can advance"

ship_completion=$(section_text "$SHIP" "## Completion Criteria" "## Cancel")
assert_contains "$ship_completion" 'durably recorded as `void`/`skipped`' "ship top-level criteria ignore durable review recovery"
assert_contains "$ship_completion" "exact current head passes CI" "ship durable recovery is not anchored to current-head CI"
assert_contains "$ship_completion" "unrecorded timeout" "ship local exits can bypass top-level criteria"

complete_completion=$(section_text "$COMPLETE" "## Completion Criteria" "## Further Reading")
assert_contains "$complete_completion" "durably recorded as void" "complete-issue top-level criteria ignore durable review recovery"
assert_contains "$complete_completion" "ordinary timeout or fallback failure does not count" "complete-issue local exits can bypass top-level criteria"

selection_gate=$(section_text "$WORKTREE_REMOVE" "### Step 2:" "### Step 3:")
assert_contains "$selection_gate" "equally valid" "worktree selection does not identify genuine intent"
assert_contains "$selection_gate" "stop before removal" "worktree selection can continue without a target"

branch_gate=$(section_text "$WORKTREE_REMOVE" "### Step 5:" "__END__")
assert_contains "$branch_gate" "missing-intent gate" "branch deletion does not require intent"
assert_contains "$branch_gate" "stop without deleting" "branch deletion can continue without intent"

echo "All decision gate behavior tests passed."
