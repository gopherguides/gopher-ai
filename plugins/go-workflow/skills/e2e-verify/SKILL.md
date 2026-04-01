---
name: e2e-verify
description: |
  WHEN: User wants to verify a PR end-to-end before merging, run E2E browser tests on a PR,
  investigate implementation gaps, or fix review comments and verify. Trigger on "e2e verify",
  "verify PR", "e2e test", "fix and verify", "fix and ship", "ship prep", or $e2e-verify invocation.
  WHEN NOT: User only wants to run unit tests ($verify), only ship without verification ($ship),
  only address review comments ($address-review), or only run coverage ($coverage).
argument-hint: "[PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page", "mcp__chrome-devtools-mcp__fill_form", "mcp__chrome-devtools-mcp__wait_for"]
---

# E2E Verify

## Parse Arguments

Extract PR number and mode from `$ARGUMENTS`:

```bash
MODE="verify"
PR_ARG=""
for arg in $ARGUMENTS; do
  case "$arg" in
    verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship) MODE="$arg" ;;
    *) if echo "$arg" | grep -qE '^[0-9]+$'; then PR_ARG="$arg"; fi ;;
  esac
done
echo "MODE=$MODE PR_ARG=$PR_ARG"
```

## Resolve PR Number

```bash
PR_NUM="${PR_ARG:-$(gh pr view --json number --jq '.number' 2>/dev/null)}"
if [ -z "$PR_NUM" ]; then
  echo "Error: No PR found for current branch and no PR number provided."
  echo "Usage: /e2e-verify [PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
  exit 1
fi
echo "Working on PR #$PR_NUM in mode: $MODE"
```

## Loop Initialization & Re-entry

### State File Bootstrap

```bash
STATE_FILE=".claude/e2e-verify-${PR_NUM}.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi
```

**Only call setup-loop on fresh starts** (no state file or empty phase):

```bash
if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "e2e-verify-${PR_NUM}" "VERIFIED" 30 "" \
    '{"rebasing":"Resume rebase onto base branch.","building":"Resume build verification.","addressing":"Resume address-review fixes.","investigating":"Resume investigation.","e2e-testing":"Resume E2E tests. Restart dev server if needed.","posting":"Resume posting results to PR.","shipping":"Resume ship workflow."}'
fi
```

### Persist Arguments

```bash
STATE_FILE=".claude/e2e-verify-${PR_NUM}.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg mode "$MODE" --arg pr_number "$PR_NUM" --arg build_result "" \
   --arg e2e_result "" --argjson pages_tested 0 --arg base_branch "" \
   '. + {mode: $mode, pr_number: $pr_number, build_result: $build_result, e2e_result: $e2e_result, pages_tested: $pages_tested, base_branch: $base_branch}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

### Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry. Recover state from persisted fields and skip to the corresponding phase:

- `rebasing` → go to Step 1-2
- `building` → go to Step 2
- `addressing` → go to Step 3
- `investigating` → go to Step 4
- `e2e-testing` → go to Step 5
- `posting` → go to Step 6
- `shipping` → go to Step 7

If `PHASE` is empty, this is a fresh start. Continue to Step 1.

---

## Mode Summary

| Mode | Steps Executed | Finish Action |
|------|---------------|---------------|
| `verify` (default) | 1-2, 5-6 | Report results |
| `fix-and-verify` | 1-2, 3, 5-6 | Add `run-full-ci` label, report |
| `investigate` | 1-2, 4, 5-6 | Report findings (no label) |
| `ship-prep` | 1-2, 5-6 | Add `run-full-ci` label, report |
| `ship` | 1-2, 5-6, 7 | Run `/go-workflow:ship` |
| `fix-and-ship` | 1-2, 3, 5-6, 7 | Add `run-full-ci` label → watch CI → `/go-workflow:ship` |

---

## Steps 1-2: Rebase and Build Verification

Set phase to `rebasing`:

```bash
set_loop_phase "$STATE_FILE" "rebasing"
```

Read `rebase-and-build.md` for the full rebase and build verification procedure:
- Step 1: Detect base branch, fetch, rebase if behind, force-push with lease, wait for CI
- Step 2: Run code generation, go build, go test, golangci-lint, check for generated file drift

After build verification, persist results:

```bash
set_loop_phase "$STATE_FILE" "building"
TMP="$STATE_FILE.tmp"
jq --arg build_result "$BUILD_RESULT" --arg base_branch "$BASE_BRANCH" \
   '.build_result = $build_result | .base_branch = $base_branch' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

**If build failed:** Report failure and stop. Do not proceed to E2E testing with a broken build.

---

## Step 3: Address Review (conditional)

**Only for modes: `fix-and-verify`, `fix-and-ship`**

For all other modes, skip to Step 4 or Step 5.

Set phase to `addressing`:

```bash
set_loop_phase "$STATE_FILE" "addressing"
```

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow **Steps 2-11 only**:

- **Skip Step 1** (checkout/rebase) — already done in Steps 1-2 above
- **Skip Step 12** (watch loop) — not applicable in e2e-verify context
- Do NOT create a second loop state file — all phases are managed under the e2e-verify loop

After addressing review feedback, create a descriptive fix commit and push.

---

## Step 4: Investigate (conditional)

**Only for mode: `investigate`**

For all other modes, skip to Step 5.

Set phase to `investigating`:

```bash
set_loop_phase "$STATE_FILE" "investigating"
```

1. Read the GitHub issue linked to the PR:
   ```bash
   gh pr view "$PR_NUM" --json body,title,url
   ```

2. Review the implementation against requirements:
   ```bash
   git diff "origin/${BASE_BRANCH}...HEAD"
   ```

3. Identify gaps between issue requirements and implementation:
   - Missing acceptance criteria
   - Untested edge cases
   - Potential regressions
   - Architectural concerns

4. Record findings for the PR comment. Do NOT fix anything — only report.

---

## Step 5: E2E Testing

Set phase to `e2e-testing`:

```bash
set_loop_phase "$STATE_FILE" "e2e-testing"
```

Read `e2e-test-execution.md` for the full E2E test procedure:
- Check MCP availability and web component indicators
- Detect and start dev server (reuse if already running)
- Run database migrations if applicable
- Perform login flow if authentication is required
- Test each changed route: navigate, screenshot, console check, network check
- Clean up and collect results

After E2E testing, persist results:

```bash
TMP="$STATE_FILE.tmp"
jq --arg e2e_result "$E2E_RESULT" --argjson pages_tested "$PAGES_TESTED" \
   '.e2e_result = $e2e_result | .pages_tested = $pages_tested' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

---

## Step 6: Post Results

Set phase to `posting`:

```bash
set_loop_phase "$STATE_FILE" "posting"
```

Read `pr-results-comment.md` for structured PR comment posting:
- Build verification results table
- E2E test results table (or skip reason)
- Investigation findings (if investigate mode)
- Mode-specific footer and labels

---

## Step 7: Finish (mode-specific)

| Mode | Action |
|------|--------|
| `verify` | Report results. Output `<done>VERIFIED</done>` |
| `fix-and-verify` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `investigate` | Report findings (no label). Output `<done>VERIFIED</done>` |
| `ship-prep` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `ship` | Set phase to `shipping`. Invoke `/go-workflow:ship` |
| `fix-and-ship` | Add `run-full-ci` label. Set phase to `shipping`. Watch CI → invoke `/go-workflow:ship --skip-coverage` |

For `fix-and-ship` mode, watch CI before shipping:

```bash
set_loop_phase "$STATE_FILE" "shipping"
gh pr edit "$PR_NUM" --add-label "run-full-ci"
for i in 1 2 3; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

Then invoke `/go-workflow:ship --skip-coverage` to avoid re-running coverage and E2E tests that were already done.

---

## Completion Criteria

Output `<done>VERIFIED</done>` when ALL of these are true:

1. Branch rebased onto base (or already up to date)
2. Build passes (go build, go test)
3. Review addressed (if `fix-and-verify` or `fix-and-ship` mode)
4. E2E tests completed (pass or skipped — never blocks)
5. Results posted to PR as a comment
6. Mode-specific finish action completed

**When ALL criteria are met, output exactly:** `<done>VERIFIED</done>`

**Safety:** If 15+ iterations without success, document blockers and ask user.

---

## Supporting Files

- `rebase-and-build.md` — Steps 1-2: rebase onto base branch + build verification
- `e2e-test-execution.md` — Step 5: Chrome DevTools MCP E2E testing
- `pr-results-comment.md` — Step 6: structured PR comment with results
