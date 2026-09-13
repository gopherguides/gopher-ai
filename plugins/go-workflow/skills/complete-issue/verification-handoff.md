# Complete-Issue Verification Handoff

Loaded by `SKILL.md` Phase 3. Execute the complete E2E fix-and-ship component handoff and translate its structured result.

## Phase 3: E2E Verify and Ship

```bash
set_loop_phase "$STATE_FILE" "verifying" "$WORKFLOW_STATE_PATH"
E2E_VERIFY_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "e2e_verify")
initialize_workflow_state "$STATE_FILE" "$E2E_VERIFY_STATE_PATH"
```

Read `<PLUGIN_ROOT>/skills/e2e-verify/SKILL.md` and execute its workflow
directly, treating `$PR_NUM fix-and-ship` as its `SKILL_ARGS`. Do not call the
Skill tool. This runs the full workflow in `fix-and-ship` mode (rebase, build,
address review, E2E browser tests, post results, add the `run-full-ci` label,
watch CI, and execute the ship workflow).

Before executing the loaded workflow, set its explicit caller contract:

```bash
CALLER_LOOP_STATE_FILE="$STATE_FILE"
CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"
```

After it returns, clear both caller variables and translate its structured
result into complete-issue's own terminal contract:

```bash
WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"
unset CALLER_LOOP_STATE_FILE CALLER_WORKFLOW_STATE_PATH
E2E_VERIFY_RESULT=$(get_loop_field "$STATE_FILE" "result" "$E2E_VERIFY_STATE_PATH")
E2E_VERIFY_REASON=$(get_loop_field "$STATE_FILE" "reason" "$E2E_VERIFY_STATE_PATH")
if [ "$E2E_VERIFY_RESULT" != "verified" ]; then
  E2E_VERIFY_REASON="${E2E_VERIFY_REASON:-e2e-verify-incomplete}"
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$E2E_VERIFY_REASON" "incomplete" "INCOMPLETE"
  echo "Complete-issue stopped during verification: $E2E_VERIFY_REASON"
  echo "<done>INCOMPLETE</done>"
  exit 0
fi
```

---

## Owner Completion Result

Run only after every completion criterion in the router is satisfied:

```bash
set_loop_terminal_result "$STATE_FILE" "complete" "" "completed" "COMPLETE"
echo "<done>COMPLETE</done>"
```
