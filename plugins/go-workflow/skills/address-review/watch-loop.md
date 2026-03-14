# Watch Loop: Bot Re-review Monitoring

## Phase Transition

Before entering the watch loop, update the loop state phase so that any stop-hook re-entry resumes at Step 12 instead of restarting the fix cycle:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.json"
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

**If ALL detected bots are done → output `<done>COMPLETE</done>` and stop.**

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

4. **Timeout:** If 5 minutes pass with no new activity from any bot AND bots haven't approved:
   - Use `AskUserQuestion` to ask: "Bots haven't responded after 5 minutes. Would you like to keep waiting, re-trigger bot reviews, or exit?"
   - If "keep waiting" → reset timeout, continue polling
   - If "re-trigger" → go to 12d
   - If "exit" → output `<done>COMPLETE</done>`

### 12c. New comments found — loop back to Step 2

After the quiet period ends and new unresolved comments/threads exist:

**First, clear the `watching` phase** so stop-hook re-entry runs the fix cycle instead of skipping to Step 12:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".claude/${SAFE_LOOP_NAME}.loop.local.json"
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
4. If 3 attempts exhausted → use `AskUserQuestion`: "Bot <login> hasn't approved after 3 re-trigger attempts. Keep trying, skip this bot, or exit?"
5. After re-triggering → return to 12b to wait again.
