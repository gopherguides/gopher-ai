---
argument-hint: "[PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
description: "Run E2E verification on a PR: rebase, build, browser test, post results"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page", "mcp__chrome-devtools-mcp__fill_form", "mcp__chrome-devtools-mcp__wait_for"]
---

# E2E Verify

**If `$ARGUMENTS` is empty or not provided:**

Display usage information:

**Usage:** `/e2e-verify [PR-number] [mode]`

**Modes:**

| Mode | When to use | Flow |
|------|-------------|------|
| `verify` (default) | Code looks solid, just needs E2E | Rebase → build → E2E test → post results |
| `fix-and-verify` | Review feedback needs addressing | Address review → rebase → build → E2E → post → add `run-full-ci` label |
| `investigate` | Not sure the implementation is right | Rebase → read issue → review gaps → E2E → report findings |
| `ship-prep` | Confident, want to prep for /ship | Rebase → build → E2E → post → add `run-full-ci` label |
| `ship` | Ready end-to-end (no review to address) | Rebase → build → E2E → post → `/go-workflow:ship` |
| `fix-and-ship` | Take PR to completion (most common) | Address review → rebase → build → E2E → post → label → watch CI → `/go-workflow:ship` |

**Examples:**
- `/e2e-verify` — verify current branch's PR
- `/e2e-verify 42` — verify PR #42
- `/e2e-verify fix-and-ship` — fix review comments and ship
- `/e2e-verify 42 investigate` — investigate PR #42

Ask the user: "What PR would you like to verify? (or provide a PR number and mode)"

---

**If `$ARGUMENTS` is provided:**

## Validate PR Context

First, resolve the PR number and validate it exists before creating loop state:

```bash
PR_NUM=""
for arg in $ARGUMENTS; do
  case "$arg" in
    verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship) ;;
    *) if [ -z "$PR_NUM" ] && echo "$arg" | grep -qE '^[0-9]+$'; then PR_NUM="$arg"; fi ;;
  esac
done
PR_NUM="${PR_NUM:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"

if [ -z "$PR_NUM" ]; then
  echo "Error: No PR found for current branch and no PR number provided."
  echo "Usage: /e2e-verify [PR-number] [mode]"
  exit 1
fi

gh pr view "$PR_NUM" --json number >/dev/null 2>&1 || { echo "Error: PR #$PR_NUM does not exist"; exit 1; }
echo "Verified PR #$PR_NUM exists"
```

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh"; exit 1; else PR_NUM=""; for arg in $ARGUMENTS; do case "$arg" in verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship) ;; *) if [ -z "$PR_NUM" ] && echo "$arg" | grep -qE "^[0-9]+$"; then PR_NUM="$arg"; fi ;; esac; done; PR_NUM="${PR_NUM:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"; if [ -z "$PR_NUM" ]; then echo "No PR found — skipping loop init"; exit 1; fi; "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "e2e-verify-${PR_NUM}" "VERIFIED" 30; fi`

## Execute

Read `${CLAUDE_PLUGIN_ROOT}/skills/e2e-verify/SKILL.md` and follow all steps with the parsed PR number and mode from `$ARGUMENTS`.
