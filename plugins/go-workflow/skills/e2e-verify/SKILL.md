---
name: e2e-verify
description: "Run end-to-end PR verification with browser testing. Use before merge or in fix-and-ship mode when the user asks to verify a PR, run E2E, browser-test, or visually check UI changes. SKIP backend-only checks with no browser/UI path; use review-deep or ship as appropriate."
argument-hint: "[PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
disable-model-invocation: true
---

# E2E Verify

Before requesting decisions or delegating work, read
`${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `${CLAUDE_PLUGIN_ROOT}/lib/decision-gates.md` before resolving a missing
target or other workflow choice.

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/github-rest.sh"
```

## Core Principle: Visual Verification is Non-Negotiable

**Every screenshot you take MUST be read and visually inspected.** Taking a screenshot without reading it is useless. The entire point of E2E testing is to verify what the USER sees, not just what the DOM contains.

After every `mcp__chrome-devtools-mcp__take_screenshot`, you MUST:

1. **Read the screenshot** using your multimodal vision capabilities
2. **Compare it to the spec** — read the issue/PR description and verify the screenshot matches what was requested
3. **Describe what you see** — document the visual state in your results (layout, content, styling, errors)
4. **Flag discrepancies** — if what you see doesn't match the spec, report it as a finding

DOM checks (console errors, network requests) supplement visual verification — they do NOT replace it. A page can have zero console errors and zero network failures but still look completely wrong.

---

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
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
WORKTREE_PATH="${WORKTREE_PATH:-$CURRENT_CHECKOUT_ROOT}"
if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] ||
   [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  echo "ERROR: Could not resolve absolute repository paths."
  exit 1
fi
CURRENT_REPO_SLUG=$(cd "$WORKTREE_PATH" && gh api "repos/{owner}/{repo}" --jq '.full_name')
REPO_SLUG="${REPO_SLUG:-$CURRENT_REPO_SLUG}"
PR_JSON=""
if [ -n "$PR_ARG" ]; then
  PR_NUM="$PR_ARG"
  if ! PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM" 2>/dev/null); then
    echo "Error: PR #$PR_NUM does not exist"
    exit 1
  fi
elif PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null); then
  PR_NUM=$(jq -er '.number' <<< "$PR_JSON")
else
  PR_NUM=""
fi

if [ -z "$PR_NUM" ]; then
  echo "Claude Code: /go-workflow:e2e-verify [PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
  echo "Codex: \$go-workflow:e2e-verify [PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
else
  echo "Working on PR #$PR_NUM in mode: $MODE"
fi
```

If `PR_NUM` is empty, this is a **missing-intent gate**. Request the PR number
through native structured input when available; otherwise ask in the final
response and stop before loop initialization or a completion claim.

## Loop Initialization & Re-entry

Read `loop-state.md` and run the **bootstrap block** (creates state file via setup-loop, persists arguments, performs re-entry check). If `PHASE` is set, recover state and skip to the corresponding phase below; otherwise this is a fresh start.

Phase → step routing:

- `rebasing` → Step 1-2
- `building` → Step 2
- `addressing` → Step 3
- `investigating` → Step 4
- `e2e-testing` → Step 5
- `posting` → Step 6
- `shipping` → Step 7

## Hard Invariant Failure

When this skill or a supporting file reports
`WORKFLOW_RESULT=INCOMPLETE`, persist the supplied reason:

```bash
TMP="$STATE_FILE.tmp"
jq --arg reason "$WORKFLOW_REASON" \
  '.workflow_result = "incomplete" | .workflow_reason = $reason | .phase = "incomplete" | .completion_promise = "INCOMPLETE"' \
  "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

Output `<done>INCOMPLETE</done>` and stop. Never continue to E2E, add labels,
invoke ship, or output `<done>VERIFIED</done>` from an invariant-failure path.

---

## Mode Summary

| Mode | Steps Executed | Finish Action |
|------|---------------|---------------|
| `verify` (default) | 1-2, 5-6 | Report results |
| `fix-and-verify` | 1-2, 3, 5-6 | Add `run-full-ci` label, report |
| `investigate` | 1-2, 4, 5-6 | Report findings (no label) |
| `ship-prep` | 1-2, 5-6 | Add `run-full-ci` label, report |
| `ship` | 1-2, 5-6, 7 | Run the ship workflow |
| `fix-and-ship` | 1-2, 3, 5-6, 7 | Add `run-full-ci` label → watch CI → run the ship workflow |

---

## Steps 1-2: Rebase and Build Verification

```bash
set_loop_phase "$STATE_FILE" "rebasing"
```

Read `rebase-and-build.md` for the full procedure: detect base branch, fetch, rebase if behind, force-push with lease, wait for CI; then run code generation, `go -C "$WORKTREE_PATH" build`, `go -C "$WORKTREE_PATH" test`, a worktree-scoped `golangci-lint`, and check for generated-file drift.

After build verification, persist results — Read `loop-state.md` for the **persist-build-result block**.

**If build failed:** Report failure and stop. Do not proceed to E2E testing with a broken build.

---

## Step 3: Address Review (conditional)

**Only for modes: `fix-and-verify`, `fix-and-ship`** — for all others, skip to Step 4 or 5.

```bash
set_loop_phase "$STATE_FILE" "addressing"
```

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow **Steps 2-11 only**:

- **Skip Step 1** (checkout/rebase) — already done in Steps 1-2 above
- **Skip Step 12** (watch loop) — not applicable in e2e-verify context
- Do NOT create a second loop state file — all phases are managed under the e2e-verify loop

After addressing review feedback, create a descriptive fix commit and push.

### Re-verify after fixes

**CRITICAL:** Step 3 modified code, so re-run build verification before E2E:

```bash
BUILD_RESULT=pass
if ! go -C "$WORKTREE_PATH" build ./...; then
  BUILD_RESULT=fail
elif ! go -C "$WORKTREE_PATH" test ./...; then
  BUILD_RESULT=fail
elif command -v golangci-lint >/dev/null 2>&1 && ! (cd "$WORKTREE_PATH" && golangci-lint run); then
  BUILD_RESULT=fail
fi
```

If `BUILD_RESULT=fail`, report `WORKFLOW_RESULT=INCOMPLETE` and
`WORKFLOW_REASON=verification-failed`, follow **Hard Invariant Failure**, and
stop. Fix the failure before rerunning.

---

## Step 4: Investigate (conditional)

**Only for mode: `investigate`** — for all others, skip to Step 5.

```bash
set_loop_phase "$STATE_FILE" "investigating"
```

1. Refresh the PR metadata with `PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM")`, then read its requirements with `jq -r '"\(.title)\n\n\(.body // \"\")\n\n\(.html_url)"' <<< "$PR_JSON"`.
2. Review the implementation against requirements: `git -C "$WORKTREE_PATH" diff "${BASE_REMOTE}/${BASE_BRANCH}...HEAD"`
3. Identify gaps between issue requirements and implementation: missing acceptance criteria, untested edge cases, potential regressions, architectural concerns
4. Record findings for the PR comment. **Do NOT fix anything — only report.**

---

## Step 5: E2E Testing

```bash
set_loop_phase "$STATE_FILE" "e2e-testing"
```

Read the PR/issue description first to understand what the change is supposed to look like:

```bash
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || { echo "Error: Could not read PR #$PR_NUM"; exit 1; }
jq -r '"\(.title)\n\n\(.body // \"\")"' <<< "$PR_JSON"
```

Read `e2e-test-execution.md` for the full E2E test procedure: MCP availability check, dev-server detection/start, migrations, login flow, **per-route navigate → stabilize → screenshot → READ screenshot → compare to spec → document findings**, cleanup.

**CRITICAL:** Every screenshot MUST be read and visually compared against the PR/issue spec. If you take a screenshot but don't read it, you have not tested anything.

After E2E testing, persist results — Read `loop-state.md` for the **persist-e2e-result block**.

---

## Step 6: Post Results

```bash
set_loop_phase "$STATE_FILE" "posting"
```

Read `pr-results-comment.md` for the structured PR comment: build results table, E2E results table (or skip reason), investigation findings (if `investigate` mode), mode-specific footer and labels.

---

## Step 7: Finish (mode-specific, gated)

Read `mode-finish.md` for the **Step 7.0 E2E gate** (mandatory pre-check that
halts on UI-visible E2E failure with `<done>E2E_FAIL</done>`), then the mode →
finish-action mapping, the `run-full-ci` label add, the `fix-and-ship` CI
watch loop, and the user-only ship workflow handoff rules.

**Critical:** the gate is non-negotiable. UI-visible PRs that fail E2E must
exit with `<done>E2E_FAIL</done>` — no labels, no ship.

---

## Completion Criteria

The loop terminates on a `<done>…</done>` sentinel. Which sentinel you emit
depends on `E2E_RESULT` and whether the diff is UI-visible:

| `E2E_RESULT` | UI-visible diff | Non-UI diff |
|---|---|---|
| `pass` | `<done>VERIFIED</done>` | `<done>VERIFIED</done>` |
| `skipped` | not allowed — must be `pass` or a fail state | `<done>VERIFIED</done>` |
| `fail`, `partial`, `skipped-server-failed`, `missing-browser-tooling`, `uninspected-screenshots` | post comment, then `<done>E2E_FAIL</done>`. No labels, no ship. | not applicable |

Output `<done>VERIFIED</done>` only when ALL of these are true:

1. Branch rebased onto base (or already up to date)
2. Generation, build, tests, and configured lint checks pass
3. Review addressed (if `fix-and-verify` or `fix-and-ship` mode)
4. E2E gate passed per the table above (UI: `pass`; non-UI: `skipped`)
5. Results posted to PR as a comment
6. Mode-specific finish action completed (only reached when the E2E gate passed)

If the E2E gate failed on a UI-visible diff, output `<done>E2E_FAIL</done>`
after Step 6 instead. Do not invoke `$go-workflow:ship`. Do not add labels.

**Safety:** If 15+ iterations complete without success, document the blocking
evidence and stop incomplete. Do not bypass E2E or completion criteria.

---

## Further Reading

- `rebase-and-build.md` — Steps 1-2: rebase onto base branch + build verification
- `e2e-test-execution.md` — Step 5: Chrome DevTools MCP E2E testing
- `pr-results-comment.md` — Step 6: structured PR comment with results
- `loop-state.md` — bootstrap, re-entry, persist-result blocks (Steps 1-2 and Step 5)
- `mode-finish.md` — Step 7 mode → action mapping and `fix-and-ship` CI-watch loop
