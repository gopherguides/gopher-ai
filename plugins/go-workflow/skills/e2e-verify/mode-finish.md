# E2E Verify — Mode-Specific Finish Actions

Loaded by `SKILL.md` Step 7. Contains the **E2E gate** (must run before any
finish action), maps `MODE` to the closing action, and contains the
`fix-and-ship` CI-watch loop and user-only ship workflow handoff rules.

## Step 7.0: E2E Gate (applies to every mode before any finish action)

**Before** doing anything in the per-mode table below, evaluate `E2E_RESULT`:

- **UI-visible diff** (`WEB_CHANGES`, `HANDLER_CHANGES`, or layout-sensitive
  keywords detected — see `e2e-test-execution.md` §5a.1):
  - `E2E_RESULT=pass` → continue to the per-mode finish action below.
  - `E2E_RESULT` is anything else (`fail`, `partial`, `skipped-server-failed`,
    `missing-browser-tooling`, `uninspected-screenshots`) → **stop**. Do NOT
    add `run-full-ci`. Do NOT add `e2e-verified`. Do NOT invoke
    `$go-workflow:ship`. The Step 6 comment already records the failure with
    findings. Output `<done>E2E_FAIL</done>` so the loop exits without a
    verified state.
- **Non-UI diff** (no web indicators, no UI-facing files changed):
  - `E2E_RESULT=skipped` → continue to the per-mode finish action below
    (treated as the success path).
  - Any non-`skipped` value on a non-UI diff is a logic error — investigate
    before continuing.

## Step 7.1: Mode → Action Table (only reached when the gate above passed)

| Mode | Action |
|------|--------|
| `verify` | Report results. Output `<done>VERIFIED</done>` |
| `fix-and-verify` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `investigate` | Report findings (no label). Output `<done>VERIFIED</done>` |
| `ship-prep` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `ship` | Set phase to `shipping`. Execute the ship workflow |
| `fix-and-ship` | Add `run-full-ci` label. Set phase to `shipping`. Watch CI → execute the full ship workflow |

## Add the `run-full-ci` Label

For all modes that include the label step:

```bash
jq -cn '{labels: ["run-full-ci"]}' |
  gh api --method POST "repos/$REPO_SLUG/issues/$PR_NUM/labels" --input -
```

The repo's CI is gated on this label so the full test matrix only runs once
the verifier has signed off — don't add it earlier in the flow.

## `fix-and-ship` CI Watch Loop

Run after the label add. The watcher waits for check registration, pins every
poll to the exact PR head, and rejects API failures or a head shift.

```bash
set_loop_phase "$STATE_FILE" "shipping"
PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM") || {
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON=ci-api-failed
}
if [ "${WORKFLOW_RESULT:-}" != "INCOMPLETE" ]; then
  HEAD_SHA=$(jq -er '.head.sha' <<< "$PR_JSON")
  CHECKS_STATUS=0
  CHECKS_SNAPSHOT=$(cd "$WORKTREE_PATH" && github_watch_pr_checks "$PR_NUM" "$HEAD_SHA") || CHECKS_STATUS=$?
  if [ "$CHECKS_STATUS" -ne 0 ]; then
    case "$CHECKS_STATUS" in
      "$GITHUB_CHECKS_FAILED") WORKFLOW_REASON=ci-checks-failed ;;
      "$GITHUB_CHECKS_REGISTRATION_TIMEOUT") WORKFLOW_REASON=ci-registration-timeout ;;
      "$GITHUB_CHECKS_API_ERROR") WORKFLOW_REASON=ci-api-failed ;;
      "$GITHUB_CHECKS_HEAD_SHIFT") WORKFLOW_REASON=pr-head-shift ;;
      *) WORKFLOW_REASON=ci-watch-failed ;;
    esac
    WORKFLOW_RESULT=INCOMPLETE
  fi
fi

if [ "${WORKFLOW_RESULT:-}" = "INCOMPLETE" ]; then
  echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  exit 1
fi
jq -r '.items[] | "\(.name): \(.state)"' <<< "$CHECKS_SNAPSHOT"
```

Every non-success watcher result follows the top-level **Hard Invariant
Failure** procedure. Do not continue to the ship workflow.

## Ship Workflow Handoff

The ship skill is user-only. Do not call it with the Skill tool. Read
`${CLAUDE_PLUGIN_ROOT}/skills/ship/SKILL.md` and execute its instructions
directly.

- **`ship` mode** → Treat an empty string as the ship workflow's `$ARGUMENTS`
  so it runs the full coverage and E2E gates.
- **`fix-and-ship` mode** → Treat an empty string as the ship workflow's
  `$ARGUMENTS`. Ship must run its changed-source coverage gate; the earlier
  browser result may be reused only through ship's explicit verified-result
  path.
