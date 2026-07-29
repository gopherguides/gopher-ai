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

review_capacity=$(section_text "$REVIEW_PLAN" "Follow the displayed plan" "__END__")
assert_contains "$review_capacity" "further partitioning" "review planning cannot recover from capacity limits"
assert_contains "$review_capacity" "higher-capacity backend" "review planning cannot use backend evidence"
assert_contains "$review_capacity" "explicitly selected backend" "review planning can override explicit backend intent"
assert_contains "$review_capacity" "baseline coverage cannot be narrowed" "review planning can waive coverage"

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
assert_contains "$bot_exhaustion" "3 attempts are exhausted" "bot re-trigger lacks a bounded limit"
assert_contains "$bot_exhaustion" "bot-approval-exhausted" "bot exhaustion lacks incomplete reason"
assert_contains "$bot_exhaustion" "follow **Incomplete" "bot exhaustion can claim completion"

bot_success=$(section_text "$ADDRESS_WATCH" "### 12a." "### 12b.")
assert_contains "$bot_success" "return control to ship Step 13" "nested bot watch can terminate ship early"
assert_contains "$bot_success" "standalone address-review" "standalone bot watch lacks its completion outcome"
assert_contains "$bot_success" "top-level completion criteria" "caller completion criteria are not authoritative"

dirty_review=$(section_text "$ADDRESS_FIX" "### Protect Pre-existing Target Changes" "### Parallel Fix Dispatch")
assert_contains "$dirty_review" "pre-existing diff" "review ownership gate does not inspect evidence"
assert_contains "$dirty_review" "do not edit or stage" "review ownership gate can capture unrelated hunks"
assert_contains "$dirty_review" "WORKFLOW_REASON=unowned-review-target-changes" "review ownership gate lacks incomplete outcome"

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
