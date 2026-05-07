# Complete Issue — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry". The state file path is
always `.local/state/complete-issue-${ISSUE_NUM}.loop.local.json` relative to
the original repo (NOT the worktree — Phase 1 reassigns `STATE_FILE` to an
absolute path once the worktree exists).

## Bootstrap Block

```bash
STATE_FILE=".local/state/complete-issue-${ISSUE_NUM}.loop.local.json"
if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "complete-issue-${ISSUE_NUM}" "COMPLETE" 100 "" \
    '{"implementing":"Resume start-issue implementation.","reviewing":"Resume codex review.","verifying":"Resume E2E verification and shipping."}'
fi
```

## Persist Arguments Block

```bash
TMP="$STATE_FILE.tmp"
jq --arg issue_num "$ISSUE_NUM" --arg flags "$FLAGS" --arg pr_number "" \
   '. + {issue_num: $issue_num, flags: $flags, pr_number: $pr_number}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set, recover state and skip to the corresponding phase listed
in the SKILL.md phase routing table. If `PHASE` is empty, continue to
Phase 1.
