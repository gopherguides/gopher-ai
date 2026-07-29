# Watch Loop: Bot Re-review Monitoring

## Phase Transition

Before entering the watch loop, update the loop state phase so that any stop-hook re-entry resumes at Step 12 instead of restarting the fix cycle:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".local/state/${SAFE_LOOP_NAME}.loop.local.json"
if [ -f "$LOOP_STATE_FILE" ]; then
  source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
  set_loop_phase "$LOOP_STATE_FILE" "watching"
  echo "Phase set to: watching"
fi
```

**Note:** `BOT_REVIEW_BASELINE` should already be set from Step 6 (right after the push). If for some reason it wasn't captured earlier (e.g., re-entry after context loss), capture it now as a fallback.

**CRITICAL: Persist the baseline in the state file** so it survives context-loss re-entry:

```bash
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline captured (fallback): $BOT_REVIEW_BASELINE"
fi

if [ -f "$LOOP_STATE_FILE" ]; then
  set_loop_field "$LOOP_STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE"
  echo "Bot review baseline persisted: $BOT_REVIEW_BASELINE"
fi
```

## Incomplete Approval Outcome

If a terminal path is reached before every detected bot approves, do not report
the workflow as complete. Set `APPROVAL_REASON` to the reason code specified by
the decision branch, then persist the incomplete outcome:

```bash
APPROVAL_REASON="${APPROVAL_REASON:?approval reason is required}"
APPROVAL_STATE_FILE="${STATE_FILE:-${LOOP_STATE_FILE:-}}"
if [ -z "$APPROVAL_STATE_FILE" ] || [ ! -f "$APPROVAL_STATE_FILE" ]; then
  echo "Error: Cannot persist incomplete approval outcome without loop state."
  exit 1
fi

source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_field "$APPROVAL_STATE_FILE" "approval_result" "incomplete"
set_loop_field "$APPROVAL_STATE_FILE" "approval_reason" "$APPROVAL_REASON"
set_loop_phase "$APPROVAL_STATE_FILE" "approval-incomplete"
set_loop_field "$APPROVAL_STATE_FILE" "completion_promise" "INCOMPLETE"
echo "Address-review stopped without required bot approvals: $APPROVAL_REASON"
```

`STATE_FILE` is the caller-owned state used when ship consumes Steps 12a-12d; standalone address-review falls back to `LOOP_STATE_FILE`. After the state update succeeds, output `<done>INCOMPLETE</done>` and stop. The changed completion promise lets the active caller's stop hook accept the distinct terminal marker, while `approval_result` and `approval_reason` give callers a machine-readable outcome before loop cleanup.

---

## Step 12: Watch for Bot Re-review (default, skipped with --no-watch)

**Skip this entire step if `WATCH_MODE` is `false` or no review bots were detected in the Bot Discovery step.**

**NEVER check for, trigger, or mention a bot that was NOT found in the Bot Discovery step. If Bot Discovery found zero bots, you MUST skip this entire step.**

### 12a. Check if all detected bots have approved

**ONLY check bots that were discovered in the Bot Discovery step above. If no bots were discovered, skip Step 12 entirely.**

For each bot from your Bot Discovery results, use the approval detection logic from the Bot Registry (`bot-registry.md`) to determine if it has approved. The detection approaches by bot type:

- Bots with formal review states (e.g., CodeRabbit): Query latest review state
- Bots with issue comment signals: Check latest issue comment body
- Bots with status checks (e.g., Greptile): Check `gh pr checks`
- Bots with timestamp-based detection (e.g., Copilot, Claude): Compare against BOT_REVIEW_BASELINE

**Do NOT run checks for bots that were not in your Bot Discovery results.**

**If ALL detected bots are done:**

- When ship loaded this watch loop, return control to ship Step 13 without
  emitting a completion marker.
- In standalone address-review, output `<done>COMPLETE</done>` and stop.

The calling workflow's top-level completion criteria own its completion marker.

### 12b. Wait for bot re-review (quiet period detection)

If any bot hasn't approved yet:

1. **Record baseline:** Get the current count of reviews + thread comments per pending bot.

2. **Poll every 15 seconds:**
   ```bash
   sleep 15
   ```
   Then re-query review/comment counts via the same GraphQL queries.

3. **Quiet period detection:**
   - If counts changed since last poll → reset quiet timer, bot is still posting. Keep polling.
   - If counts are stable for 2 consecutive polls (30 seconds of no new activity) → bot has finished posting. Proceed to 12c.

4. **Timeout:** If 5 minutes pass with no new activity from any bot and bots
   have not approved, resolve a **driver-resolvable gate** from the bot registry
   and observed activity:
   - If every pending bot has a re-review trigger, state `Decision`, `Evidence`,
     and `Rationale`, then go to 12d.
   - If any pending bot has no trigger, set
     `APPROVAL_REASON="bot-approval-timeout"`, follow **Incomplete Approval
     Outcome**, and stop.

### 12c. New comments found — loop back to Step 2

After the quiet period ends and new unresolved comments/threads exist:

**First, clear the `watching` phase** so stop-hook re-entry runs the fix cycle instead of skipping to Step 12:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".local/state/${SAFE_LOOP_NAME}.loop.local.json"
if [ -f "$LOOP_STATE_FILE" ]; then
  source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
  set_loop_phase "$LOOP_STATE_FILE" "fixing"
  echo "Phase reset to: fixing (new bot feedback detected)"
fi
```

Then:

1. Re-fetch all review feedback (Step 2) but **only address NEW unresolved comments** from bots. Already-resolved threads stay resolved.
2. Loop back through Steps 2-11 for the new feedback only.
3. After completing the fix cycle, return to Step 12a to re-check approval status (the Phase Transition section will set phase back to `watching`).

### 12d. No new comments but bot hasn't approved — re-trigger

If a bot's quiet period ended with no new comments but it still hasn't approved:

1. Look up the bot's re-review trigger command from the Bot Registry (`bot-registry.md`).
2. If a trigger exists → post it:
   ```bash
   gh pr comment "$PR_NUM" --body "<trigger command>"
   ```
3. **Max 3 re-trigger attempts per bot.** Track the count.
4. After the third unsuccessful re-review trigger:
   - Report the `Decision`, `Evidence`, and `Rationale`.
   - Record `bot-approval-exhausted` as the approval reason.
   - Follow **Incomplete Approval Outcome** and stop.

   Bot approval remains a caller-owned completion condition.
5. After re-triggering, return to 12b to wait again.
