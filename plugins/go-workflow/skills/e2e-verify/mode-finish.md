# E2E Verify — Mode-Specific Finish Actions

Loaded by `SKILL.md` Step 7. Maps `MODE` to the closing action and contains
the `fix-and-ship` CI-watch loop and `/go-workflow:ship` invocation rules.

## Mode → Action Table

| Mode | Action |
|------|--------|
| `verify` | Report results. Output `<done>VERIFIED</done>` |
| `fix-and-verify` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `investigate` | Report findings (no label). Output `<done>VERIFIED</done>` |
| `ship-prep` | Add `run-full-ci` label. Report results. Output `<done>VERIFIED</done>` |
| `ship` | Set phase to `shipping`. Invoke `/go-workflow:ship` |
| `fix-and-ship` | Add `run-full-ci` label. Set phase to `shipping`. Watch CI → invoke `/go-workflow:ship --skip-coverage` |

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

## Ship Invocation Rules

- **`ship` mode** → `/go-workflow:ship` (full coverage + e2e gates).
- **`fix-and-ship` mode** → `/go-workflow:ship --skip-coverage`. Coverage and
  E2E tests already ran in Steps 1-2 and Step 5 of this skill, so re-running
  them in `/ship` would be wasted work and could surface flakes that were
  already accepted.
