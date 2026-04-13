---
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
description: "Complete a GitHub issue end-to-end: implement, review, E2E verify, ship"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "EnterPlanMode", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page", "mcp__chrome-devtools-mcp__fill_form", "mcp__chrome-devtools-mcp__wait_for", "mcp__chrome-devtools-mcp__evaluate_script"]
---

# Complete Issue

**If `$ARGUMENTS` is empty or not provided:**

Display usage information:

**Usage:** `/complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]`

The ultimate pipeline: **issue number in → merged PR out.**

1. Implements the issue via `/start-issue` (TDD, tests, PR)
2. Runs codex self-review and addresses findings
3. Runs E2E verification and ships via `/e2e-verify fix-and-ship`

**Examples:**
- `/complete-issue 42` — complete issue #42 end-to-end
- `/complete-issue 42 --skip-coverage` — skip coverage gate
- `/complete-issue 42 --no-agents` — single-session mode

Ask the user: "What issue number would you like to complete?"

---

**If `$ARGUMENTS` is provided:**

## Security Validation & Issue Number Extraction

Extract issue number as the first positional argument (before any flags), not just the first numeric token:

```bash
ISSUE_NUM=""
SKIP_NEXT=false
for arg in $ARGUMENTS; do
  if [ "$SKIP_NEXT" = "true" ]; then
    SKIP_NEXT=false
  elif [ "$arg" = "--coverage-threshold" ]; then
    SKIP_NEXT=true
  elif echo "$arg" | grep -qE '^--'; then
    continue
  elif [ -z "$ISSUE_NUM" ] && echo "$arg" | grep -qE '^[0-9]+$'; then
    ISSUE_NUM="$arg"
  fi
done

if [ -z "$ISSUE_NUM" ]; then
  echo "Error: Issue number must be numeric."
  echo "Usage: /complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  exit 1
fi
echo "Completing issue #$ISSUE_NUM"
```

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh"; exit 1; else ISSUE_NUM=""; SKIP_NEXT=false; for arg in $ARGUMENTS; do if [ "$SKIP_NEXT" = "true" ]; then SKIP_NEXT=false; elif [ "$arg" = "--coverage-threshold" ]; then SKIP_NEXT=true; elif echo "$arg" | grep -qE "^--"; then continue; elif [ -z "$ISSUE_NUM" ] && echo "$arg" | grep -qE "^[0-9]+$"; then ISSUE_NUM="$arg"; fi; done; if [ -z "$ISSUE_NUM" ]; then echo "Error: no issue number"; exit 1; fi; "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "complete-issue-${ISSUE_NUM}" "COMPLETE" 100; fi`

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/skills/complete-issue/SKILL.md` and follow all phases with the parsed issue number and flags from `$ARGUMENTS`.
