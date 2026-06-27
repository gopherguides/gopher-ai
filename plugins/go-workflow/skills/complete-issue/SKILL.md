---
name: complete-issue
description: "Take a GitHub issue from implementation to merged PR. Use for 'complete issue #N', 'finish this issue end-to-end', or fully autonomous issue-to-merge requests."
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "EnterPlanMode", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page", "mcp__chrome-devtools-mcp__fill_form", "mcp__chrome-devtools-mcp__wait_for", "mcp__chrome-devtools-mcp__evaluate_script"]
disable-model-invocation: true
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

Read `loop-state.md` and run the **bootstrap block** + **re-entry check**. If `PHASE` is set, recover state and skip to the corresponding phase below; otherwise continue to Phase 1.

Phase → step routing:

- `implementing` → Phase 1
- `reviewing` → Phase 2
- `verifying` → Phase 3

---

## Phase 1: Implement (`/start-issue`)

```bash
set_loop_phase "$STATE_FILE" "implementing"
```

Invoke `/go-workflow:start-issue $ISSUE_NUM $FLAGS`. Read `phases.md` for the full sub-step list (fetch issue, create worktree, detect type, explore, design, TDD, verify, coverage, security review, commit/push/PR, watch CI).

After `/start-issue` completes, detect the PR number and worktree context, reassign `STATE_FILE` to an absolute path (because CWD may have changed if a worktree was created), and persist:

```bash
PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)

GIT_DIR_ABS=$(cd "$(git rev-parse --git-dir 2>/dev/null)" && pwd)
GIT_COMMON_ABS=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)
if [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  WORKTREE_PATH=$(pwd)
  echo "Running in worktree: $WORKTREE_PATH"
fi

STATE_FILE="$(pwd)/.local/state/complete-issue-${ISSUE_NUM}.loop.local.json"
mkdir -p "$(dirname "$STATE_FILE")"

TMP="$STATE_FILE.tmp"
jq --arg pr_number "$PR_NUM" --arg worktree_path "${WORKTREE_PATH:-}" \
   '.pr_number = $pr_number | .worktree_path = $worktree_path' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
echo "PR #$PR_NUM created"
```

> **Worktree-CWD invariant (decision-time, must stay in trunk):** If a worktree was created, all subsequent phases MUST operate from `$WORKTREE_PATH`. Prefix every Bash command with `cd "$WORKTREE_PATH" &&` and use `$WORKTREE_PATH` as the base for all Read/Edit/Write file paths. The pre-tool-use hook will block tool calls targeting the wrong directory. The `STATE_FILE` reassignment above ensures `set_loop_phase` calls resolve correctly regardless of CWD.

---

## Phase 2: Self-Review (Codex)

```bash
set_loop_phase "$STATE_FILE" "reviewing"
```

Run an LLM review to catch issues before E2E verification. **CRITICAL: Never silently fall back** — always present the user with options if codex fails.

Detect codex availability:

```bash
CODEX_AVAILABLE=false
if command -v codex &>/dev/null; then
  CODEX_CMD="codex"
  CODEX_AVAILABLE=true
elif npx -y codex --version &>/dev/null 2>&1; then
  CODEX_CMD="npx -y codex"
  CODEX_AVAILABLE=true
fi
```

- **If codex is NOT available** OR **if codex exec fails at runtime** → Read `codex-fallback.md` and follow the `AskUserQuestion` flow for the matching scenario. Do NOT silently fall back.
- **If codex IS available** → run codex review on the PR diff with an adaptive timeout, address findings, and commit fixes. See `phases.md` for the full bash (diff sizing, timeout calculation, large-diff warning).

Address findings: for each valid finding, make the fix. Skip false positives or cosmetic-only items. Commit fixes if any changes were made:

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

Invoke `/go-workflow:e2e-verify $PR_NUM fix-and-ship`. This runs the full e2e-verify workflow in `fix-and-ship` mode (rebase, build, address review, E2E browser tests, post results, add `run-full-ci` label, watch CI, invoke `/go-workflow:ship`).

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

## Further Reading

- `phases.md` — full sub-step lists for Phase 1 (`/start-issue`) and the codex run for Phase 2
- `loop-state.md` — bootstrap, re-entry, and persist blocks
- `codex-fallback.md` — `AskUserQuestion` flows for codex unavailable / runtime failure / timeout
