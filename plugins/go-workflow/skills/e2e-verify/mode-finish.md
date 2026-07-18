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
    `$ship`. The Step 6 comment already records the failure with
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
| `fix-and-ship` | Add `run-full-ci` label. Set phase to `shipping`. Watch CI → execute the ship workflow with `--skip-coverage` |

## Add the `run-full-ci` Label

For all modes that include the label step:

```bash
gh pr edit "$PR_NUM" --add-label "run-full-ci"
```

The repo's CI is gated on this label so the full test matrix only runs once
the verifier has signed off — don't add it earlier in the flow.

## `fix-and-ship` CI Watch Loop

Run after the label add. Three retries with a short backoff handle the case
where `gh pr checks --watch` exits before the new CI run is registered.

```bash
set_loop_phase "$STATE_FILE" "shipping"
gh pr edit "$PR_NUM" --add-label "run-full-ci"
for i in 1 2 3; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

## Ship Workflow Handoff

The ship skill is user-only. Do not call it with the Skill tool. Read
`${CLAUDE_PLUGIN_ROOT}/skills/ship/SKILL.md` and execute its instructions
directly.

- **`ship` mode** → Treat an empty string as the ship workflow's `$ARGUMENTS`
  so it runs the full coverage and E2E gates.
- **`fix-and-ship` mode** → Treat `--skip-coverage` as the ship workflow's
  `$ARGUMENTS`. Coverage and E2E tests already ran in Steps 1-2 and Step 5 of
  this skill, so re-running them would be wasted work and could surface flakes
  that were already accepted.
