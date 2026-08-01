---
name: complete-issue
description: "Take a GitHub issue from implementation to merged PR. Use for 'complete issue #N', 'finish this issue end-to-end', or fully autonomous issue-to-merge requests. SKIP issue startup without merge intent; use start-issue."
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
disable-model-invocation: true
---

# Complete Issue

Autonomous end-to-end pipeline: **issue number in → merged PR out.**

Before requesting decisions, entering a planning workflow, or delegating work,
read `${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `${CLAUDE_PLUGIN_ROOT}/lib/decision-gates.md` before resolving any workflow
choice.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/github-rest.sh"
```

Chains the `start-issue` workflow, Codex review, and the `e2e-verify`
`fix-and-ship` workflow.

The component workflow skills are user-only. Do not call them with the Skill
tool. Load their `SKILL.md` files with Read and execute their instructions
directly with the arguments specified below.

The `$go-workflow:start-issue` phase owns subagent model tiering through agent prompt
frontmatter: Explore uses Haiku, Spec Review and Quality Review use Sonnet,
and Implementer inherits the parent session model. To override all subagent
models for a run, set `CLAUDE_CODE_SUBAGENT_MODEL=<model>` before invoking
`$go-workflow:complete-issue`; pass `--no-agents` through to run the start phase without
subagents.

## Parse Arguments

```bash
ISSUE_NUM=""
FLAGS=""
SKIP_NEXT=false
for arg in $ARGUMENTS; do
  if [ "$SKIP_NEXT" = "true" ]; then
    FLAGS="$FLAGS $arg"
    SKIP_NEXT=false
  elif [ "$arg" = "--coverage-threshold" ]; then
    FLAGS="$FLAGS $arg"
    SKIP_NEXT=true
  elif echo "$arg" | grep -qE '^--'; then
    FLAGS="$FLAGS $arg"
  elif [ -z "$ISSUE_NUM" ] && echo "$arg" | grep -qE '^[0-9]+$'; then
    ISSUE_NUM="$arg"
  else
    FLAGS="$FLAGS $arg"
  fi
done

if [ -z "$ISSUE_NUM" ]; then
  echo "Claude Code: /go-workflow:complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  echo "Codex: \$go-workflow:complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
fi

echo "Issue: $ISSUE_NUM | Flags: $FLAGS"
```

If `ISSUE_NUM` is empty, this is a **missing-intent gate**. Request the issue
number through native structured input when available; otherwise ask in the
final response and stop before loop initialization or a completion claim.

## Loop Initialization & Re-entry

Read `loop-state.md` and run the **bootstrap block**, **persist arguments
block**, and **re-entry check**. If `PHASE` is set, recover the owner phase and
the corresponding component phase before routing below; otherwise continue to
Phase 1.

Phase → step routing:

- `implementing` → Phase 1, using `.components.start_issue.phase`
- `reviewing` → Phase 3; the earlier in-session review is void and must not be restarted
- `verifying` → Phase 3, using `.components.e2e_verify.phase` and its nested
  active component
- `incomplete` → display the persisted component-aware `reason`, output
  `<done>INCOMPLETE</done>`, and stop without entering Phase 3

Resolve child phases without replacing the owner phase used by this routing
table:

```bash
OWNER_PHASE="$PHASE"
START_ISSUE_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "start_issue")
E2E_VERIFY_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "e2e_verify")
START_ISSUE_PHASE=$(get_loop_field "$STATE_FILE" "phase" "$START_ISSUE_STATE_PATH")
E2E_VERIFY_PHASE=$(get_loop_field "$STATE_FILE" "phase" "$E2E_VERIFY_STATE_PATH")
PHASE="$OWNER_PHASE"
```

---

## Phase 1: Implement (`$go-workflow:start-issue`)

```bash
set_loop_phase "$STATE_FILE" "implementing" "$WORKFLOW_STATE_PATH"
START_ISSUE_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "start_issue")
initialize_workflow_state "$STATE_FILE" "$START_ISSUE_STATE_PATH"
```

Read `${CLAUDE_PLUGIN_ROOT}/skills/start-issue/SKILL.md` and execute its workflow
directly, treating `$ISSUE_NUM $FLAGS` as its `$ARGUMENTS`. Do not call the
Skill tool. Read `phases.md` for the full sub-step list (fetch issue, create
worktree, detect type, explore, design, TDD, verify, coverage, security review,
commit/push/PR, watch CI).

Before executing the loaded workflow, set its explicit caller contract:

```bash
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

After it returns, clear both caller variables and route its structured result:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
START_ISSUE_RESULT=$(get_loop_field "$STATE_FILE" "result" "$START_ISSUE_STATE_PATH")
START_ISSUE_REASON=$(get_loop_field "$STATE_FILE" "reason" "$START_ISSUE_STATE_PATH")
if [ "$START_ISSUE_RESULT" != "complete" ]; then
  START_ISSUE_REASON="${START_ISSUE_REASON:-start-issue-incomplete}"
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$START_ISSUE_REASON" "incomplete" "INCOMPLETE"
  echo "Complete-issue stopped during implementation: $START_ISSUE_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 0
fi
```

After `$go-workflow:start-issue` completes, detect the PR number and worktree
context while retaining the already-normalized caller state path, then persist:

```bash
WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
START_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
if [ "$START_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
   [ -z "$WORKTREE_PATH" ] ||
   [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] ||
   [ ! -d "$WORKTREE_PATH" ] ||
   ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v expected="$WORKTREE_PATH" '$0 == expected { found = 1 } END { exit found ? 0 : 1 }' ||
   [ -z "$REPO_SLUG" ]; then
  WORKFLOW_REASON=start-issue-worktree-path-invalid
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 1
fi

PR_HEAD_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr "$PR_HEAD_BRANCH" "$HEAD_SHA") || {
  echo "Error: No open PR matches the persisted worktree branch and HEAD after start-issue"
  exit 1
}
PR_NUM=$(jq -er '.number' <<< "$PR_JSON")

GIT_DIR_ABS=$(cd "$WORKTREE_PATH" && cd "$(git rev-parse --git-dir 2>/dev/null)" && pwd)
GIT_COMMON_ABS=$(cd "$WORKTREE_PATH" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  echo "Running in worktree: $WORKTREE_PATH"
fi

set_loop_field "$STATE_FILE" "pr_number" "$PR_NUM" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "worktree_path" "${WORKTREE_PATH:-}" '[]'
echo "PR #$PR_NUM created"
```

> **Worktree invariant (decision-time, must stay in trunk):** All subsequent
> phases MUST operate on `$WORKTREE_PATH`. Prefer `git -C "$WORKTREE_PATH"`,
> `go -C "$WORKTREE_PATH"`, and `gh ... --repo "$REPO_SLUG"`; use an explicit
> worktree-scoped group only when no per-command option exists. Use
> `$WORKTREE_PATH` as the base for all file tools. `STATE_FILE` remains the one
> normalized caller-owned path established before Phase 1. Do not assume a
> pre-tool-use hook will correct or reject an ambient-directory command.

---

## Phase 2: Self-Review (Codex)

```bash
set_loop_phase "$STATE_FILE" "reviewing" "$WORKFLOW_STATE_PATH"
```

Run an LLM review to catch issues before E2E verification. Never silently skip
review. Resolve unpinned backend recovery from diagnostics; replacing a backend
the user explicitly required is a missing-intent gate.

Delegated fallback reviews are session-local and must complete
synchronously. Never dispatch them in the background or persist them for a
successor session. If a successor re-enters with `phase="reviewing"`, skip the
expired review and continue to Phase 3; the PR already created in Phase 1 and
its CI are the durable gate.

Detect codex availability:

```bash
CODEX_AVAILABLE=false
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
  CODEX_AVAILABLE=true
fi
```

- **If codex is NOT available** OR **if codex exec fails at runtime** → Read
  `codex-fallback.md` and follow its evidence-based recovery order.
- **If codex IS available** → run codex review on the PR diff with an adaptive timeout, address findings, and commit fixes. See `phases.md` for the full bash (diff sizing, timeout calculation, large-diff warning).

Address findings: for each valid finding, make the fix. Skip false positives or
cosmetic-only items. Maintain `REVIEW_FILES` as the exact list of files modified
in this review phase, including generated or updated tests. Before modifying an
existing path, confirm
`git -C "$WORKTREE_PATH" status --porcelain -- "$TARGET_FILE"` is empty so
pre-existing changes cannot enter the review-fix commit. Every GitHub and Git
operation in this phase runs against the persisted `WORKTREE_PATH` and
`REPO_SLUG`. Commit fixes if any changes were made:

```bash
if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
  echo "Error: Pre-existing staged changes must be committed or unstaged before complete-issue can commit review fixes."
  exit 1
fi

REVIEW_FILES=(
  "path/to/reviewed-file.go"
  "path/to/reviewed-file_test.go"
)
if [ "${#REVIEW_FILES[@]}" -gt 0 ]; then
  git -C "$WORKTREE_PATH" add -- "${REVIEW_FILES[@]}"
  if ! git -C "$WORKTREE_PATH" diff --cached --quiet; then
    git -C "$WORKTREE_PATH" commit -m "fix: address codex review findings"
    git -C "$WORKTREE_PATH" push
  fi
fi
```

---

## Phase 3: E2E Verify and Ship

```bash
set_loop_phase "$STATE_FILE" "verifying" "$WORKFLOW_STATE_PATH"
E2E_VERIFY_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "e2e_verify")
initialize_workflow_state "$STATE_FILE" "$E2E_VERIFY_STATE_PATH"
```

Read `${CLAUDE_PLUGIN_ROOT}/skills/e2e-verify/SKILL.md` and execute its workflow
directly, treating `$PR_NUM fix-and-ship` as its `$ARGUMENTS`. Do not call the
Skill tool. This runs the full workflow in `fix-and-ship` mode (rebase, build,
address review, E2E browser tests, post results, add the `run-full-ci` label,
watch CI, and execute the ship workflow).

Before executing the loaded workflow, set its explicit caller contract:

```bash
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

After it returns, clear both caller variables and translate its structured
result into complete-issue's own terminal contract:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
E2E_VERIFY_RESULT=$(get_loop_field "$STATE_FILE" "result" "$E2E_VERIFY_STATE_PATH")
E2E_VERIFY_REASON=$(get_loop_field "$STATE_FILE" "reason" "$E2E_VERIFY_STATE_PATH")
if [ "$E2E_VERIFY_RESULT" != "verified" ]; then
  E2E_VERIFY_REASON="${E2E_VERIFY_REASON:-e2e-verify-incomplete}"
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$E2E_VERIFY_REASON" "incomplete" "INCOMPLETE"
  echo "Complete-issue stopped during verification: $E2E_VERIFY_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 0
fi
```

---

## Completion Criteria

Output `<done>COMPLETE</done>` when ALL of these are true:

1. Issue implemented with tests
2. PR created and pushed
3. Codex review completed and findings addressed, or an expired session-local
   review is durably recorded as void and the exact current head passes the
   downstream CI gates. An ordinary timeout or fallback failure does not count.
4. E2E verification completed
5. Results posted to PR
6. CI passes
7. PR merged (via the ship workflow)

When all criteria are met:

```bash
set_loop_terminal_result "$STATE_FILE" "complete" "" "completed" "COMPLETE"
echo "<done>COMPLETE</done>"
```

**Safety:** If 15+ iterations complete without success, document the blocking
evidence and stop incomplete. Do not bypass a completion criterion.

## Further Reading

- `phases.md` — full sub-step lists for Phase 1 (`$go-workflow:start-issue`) and the codex run for Phase 2
- `loop-state.md` — bootstrap, re-entry, and persist blocks
- `codex-fallback.md` — evidence-based recovery for codex unavailable / runtime failure / timeout
