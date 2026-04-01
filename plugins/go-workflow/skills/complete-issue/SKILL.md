---
name: complete-issue
description: |
  WHEN: User wants to go from issue to merged PR fully autonomously. Trigger on "complete issue",
  "do issue #N end to end", "implement and ship issue", "take issue N to completion", or
  $complete-issue invocation. This is the ultimate pipeline: issue number in → merged PR out.
  WHEN NOT: User wants to start an issue without shipping ($start-issue), only ship ($ship),
  only verify ($e2e-verify), or only address review comments ($address-review).
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "EnterPlanMode", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page", "mcp__chrome-devtools-mcp__fill_form", "mcp__chrome-devtools-mcp__wait_for"]
---

# Complete Issue

Autonomous end-to-end pipeline: **issue number in → merged PR out.**

Chains: `/start-issue` → codex review → `/e2e-verify fix-and-ship`

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
  echo "Error: Issue number is required."
  echo "Usage: /complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  exit 1
fi

echo "Issue: $ISSUE_NUM | Flags: $FLAGS"
```

## Loop Initialization & Re-entry

```bash
STATE_FILE=".claude/complete-issue-${ISSUE_NUM}.loop.local.json"
if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "complete-issue-${ISSUE_NUM}" "COMPLETE" 100 "" \
    '{"implementing":"Resume start-issue implementation.","reviewing":"Resume codex review.","verifying":"Resume E2E verification and shipping."}'
fi
```

### Persist Arguments

```bash
TMP="$STATE_FILE.tmp"
jq --arg issue_num "$ISSUE_NUM" --arg flags "$FLAGS" --arg pr_number "" \
   '. + {issue_num: $issue_num, flags: $flags, pr_number: $pr_number}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

### Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set, recover state and skip to the corresponding phase:

- `implementing` → go to Phase 1
- `reviewing` → go to Phase 2
- `verifying` → go to Phase 3

---

## Phase 1: Implement (`/start-issue`)

```bash
set_loop_phase "$STATE_FILE" "implementing"
```

Invoke `/go-workflow:start-issue $ISSUE_NUM $FLAGS`.

This runs the full start-issue workflow:
1. Fetch issue details
2. Create worktree (if user chooses)
3. Detect issue type (bug/feature)
4. Explore codebase
5. Design approach (features: get user approval)
6. TDD implementation
7. Verify (build, test, lint)
8. Coverage check
9. Security review
10. Commit, push, create PR
11. Watch CI

After `/start-issue` completes, detect the PR number and worktree context:

```bash
PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)

# Detect if start-issue created a worktree (CWD may have changed)
GIT_DIR_ABS=$(cd "$(git rev-parse --git-dir 2>/dev/null)" && pwd)
GIT_COMMON_ABS=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  WORKTREE_PATH=$(pwd)
  echo "Running in worktree: $WORKTREE_PATH"
fi

# Reassign STATE_FILE to absolute path so it resolves correctly after CWD changes
STATE_FILE="$(pwd)/.claude/complete-issue-${ISSUE_NUM}.loop.local.json"

TMP="$STATE_FILE.tmp"
jq --arg pr_number "$PR_NUM" --arg worktree_path "${WORKTREE_PATH:-}" \
   '.pr_number = $pr_number | .worktree_path = $worktree_path' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
echo "PR #$PR_NUM created"
```

**If a worktree was created:** All subsequent phases MUST operate from `$WORKTREE_PATH`. Prefix every Bash command with `cd "$WORKTREE_PATH" &&` and use `$WORKTREE_PATH` as the base for all Read/Edit/Write file paths. The pre-tool-use hook will block tool calls targeting the wrong directory. The `STATE_FILE` variable has been reassigned to an absolute path so `set_loop_phase` calls resolve correctly regardless of CWD.

---

## Phase 2: Self-Review (Codex)

```bash
set_loop_phase "$STATE_FILE" "reviewing"
```

Run an LLM review to catch issues before E2E verification:

1. **Check codex availability:**
   ```bash
   if command -v codex >/dev/null 2>&1; then
     echo "Using codex for review"
   else
     echo "Codex not available — using agent-based review"
   fi
   ```

2. **If codex available:** Run codex review on the PR diff:
   ```bash
   DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
   DIFF=$(git diff "origin/${DEFAULT_BRANCH}...HEAD")
   ```
   Use `codex exec` with structured output to get all findings at once (avoids the 2-3 finding per-pass limit of interactive mode).

3. **If codex NOT available:** Use an Agent subagent to review the diff for correctness, security, and Go idioms.

4. **Address findings:** For each valid finding, make the fix. Skip findings that are false positives or cosmetic-only.

5. **Commit fixes** (if any changes were made):
   ```bash
   git add -A
   git commit -m "fix: address codex review findings"
   git push
   ```

---

## Phase 3: E2E Verify and Ship

```bash
set_loop_phase "$STATE_FILE" "verifying"
```

Invoke `/go-workflow:e2e-verify $PR_NUM fix-and-ship`.

This runs the full e2e-verify workflow in `fix-and-ship` mode:
1. Rebase onto base branch
2. Build verification
3. Address any new review feedback
4. E2E browser testing via Chrome DevTools MCP
5. Post results to PR
6. Add `run-full-ci` label
7. Watch CI
8. Invoke `/go-workflow:ship` to merge

---

## Completion Criteria

Output `<done>COMPLETE</done>` when ALL of these are true:

1. Issue implemented with tests
2. PR created and pushed
3. Codex review completed and findings addressed
4. E2E verification completed
5. Results posted to PR
6. CI passes
7. PR merged (via `/ship`)

**When ALL criteria are met, output exactly:** `<done>COMPLETE</done>`

**Safety:** If 15+ iterations without success, document blockers and ask user.
