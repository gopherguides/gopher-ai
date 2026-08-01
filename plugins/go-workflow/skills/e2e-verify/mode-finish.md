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
    findings. Persist the terminal result before exiting:

    ```bash
    WORKFLOW_RESULT=e2e-fail
    WORKFLOW_REASON="$E2E_RESULT"
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "e2e-fail" "$WORKFLOW_REASON" "e2e-failed"
    else
      set_loop_terminal_result "$STATE_FILE" "e2e-fail" "$WORKFLOW_REASON" "e2e-failed" "E2E_FAIL"
    fi
    echo "WORKFLOW_RESULT=$WORKFLOW_RESULT"
    echo "WORKFLOW_REASON=$WORKFLOW_REASON"
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      echo "E2E_VERIFY_RESULT=e2e-fail"
      echo "E2E_VERIFY_REASON=$WORKFLOW_REASON"
    else
      echo "<done>E2E_FAIL</done>"
    fi
    exit 0
    ```
- **Non-UI diff** (no web indicators, no UI-facing files changed):
  - `E2E_RESULT=skipped` → continue to the per-mode finish action below
    (treated as the success path).
  - Any non-`skipped` value on a non-UI diff is a logic error — investigate
    before continuing.

## Step 7.1: Mode → Action Table (only reached when the gate above passed)

| Mode | Action |
|------|--------|
| `verify` | Report results, then finish with a verified result |
| `fix-and-verify` | Add `run-full-ci` label, report results, then finish with a verified result |
| `investigate` | Report findings with no label, then finish with a verified result |
| `ship-prep` | Add `run-full-ci` label, report results, then finish with a verified result |
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
set_loop_phase "$STATE_FILE" "shipping" "$WORKFLOW_STATE_PATH"
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

For either ship mode, initialize ship under the current E2E workflow and set
its explicit caller contract before executing the loaded skill:

```bash
SHIP_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "ship")
initialize_workflow_state "$STATE_FILE" "$SHIP_STATE_PATH"
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

After ship returns, clear both caller variables and route its structured result:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
SHIP_RESULT=$(get_loop_field "$STATE_FILE" "result" "$SHIP_STATE_PATH")
SHIP_REASON=$(get_loop_field "$STATE_FILE" "reason" "$SHIP_STATE_PATH")
if [ "$SHIP_RESULT" != "shipped" ]; then
  WORKFLOW_RESULT=INCOMPLETE
  WORKFLOW_REASON="${SHIP_REASON:-ship-incomplete}"
fi
```

Any non-shipped result follows the top-level **Hard Invariant Failure**
procedure. A shipped result continues to the finish block below.

## Finish Result

After the selected mode action completes, persist E2E's result and either
return it to the caller or emit the standalone promise:

```bash
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "verified" "" "completed"
  echo "E2E_VERIFY_RESULT=verified"
else
  set_loop_terminal_result "$STATE_FILE" "verified" "" "completed" "VERIFIED"
  echo "<done>VERIFIED</done>"
fi
```
