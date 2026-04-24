# Loop Initialization & Re-entry Check

## Loop Initialization

!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "address-review-${RESOLVED_PR:-auto}" "COMPLETE"`

## Re-entry Check

Check if resuming from a previous watching phase:

```bash
SAFE_LOOP_NAME=$(echo "address-review-${RESOLVED_PR:-auto}" | sed 's/[^a-zA-Z0-9_-]/-/g')
LOOP_STATE_FILE=".local/state/${SAFE_LOOP_NAME}.loop.local.json"
CURRENT_PHASE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
  CURRENT_PHASE=$(jq -r '.phase // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
fi
echo "Current phase: ${CURRENT_PHASE:-<none>}"
```

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `true`:** Fix cycle already completed. Restore `BOT_REVIEW_BASELINE` from state file:

```bash
BOT_REVIEW_BASELINE=""
if [ -f "$LOOP_STATE_FILE" ]; then
  BOT_REVIEW_BASELINE=$(jq -r '.bot_review_baseline // empty' "$LOOP_STATE_FILE" 2>/dev/null || true)
fi
if [ -z "$BOT_REVIEW_BASELINE" ]; then
  BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "Bot review baseline (fallback): $BOT_REVIEW_BASELINE"
  if [ -f "$LOOP_STATE_FILE" ]; then
    set_loop_field "$LOOP_STATE_FILE" "bot_review_baseline" "$BOT_REVIEW_BASELINE"
  fi
else
  echo "Bot review baseline (restored): $BOT_REVIEW_BASELINE"
fi
```

Do NOT re-run the fix cycle. Skip to watch loop (read `watch-loop.md`).

**If `CURRENT_PHASE` is `watching` AND `WATCH_MODE` is `false`:** Clear stale phase:

```bash
if [ -f "$LOOP_STATE_FILE" ]; then
  set_loop_phase "$LOOP_STATE_FILE" ""
  echo "Phase cleared (--no-watch mode)"
fi
```

Continue with full fix cycle. **Otherwise:** Continue normally.
