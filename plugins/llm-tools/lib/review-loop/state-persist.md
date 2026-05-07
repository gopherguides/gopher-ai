# Review Loop — State Persistence

Loaded by `commands/review-loop.md` Steps 1 and 4c. The state file is
`.local/state/review-loop.loop.local.json`. Field names are part of the
re-entry contract — Step 3 reads them back. Don't rename.

## Step 1 — Initial persist (after argument parsing)

```bash
STATE_FILE=".local/state/review-loop.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg args "$ARGUMENTS" --argjson pass 0 --arg quick_mode "$QUICK_MODE" --arg gemini_tier "$GEMINI_TIER" \
   '. + {args: $args, pass: $pass, quick_mode: $quick_mode, gemini_tier: $gemini_tier}' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Step 4c — Persist scope/model selections

```bash
STATE_FILE=".local/state/review-loop.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg scope "$REVIEW_SCOPE" --arg base_branch "$BASE_BRANCH" \
   --arg model "$MODEL" --arg file_paths "${FILE_PATHS:-}" \
   '. + {scope: $scope, base_branch: $base_branch, model: $model, file_paths: $file_paths}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Per-pass updates

Every pass writes:

- `pass: <n>` (Step 5) — incremented at the start of each pass
- `quick_mode: "true"` (Step 5b, when the user picks "Use codex review --base" after a large-diff warning or codex-exec timeout)
- `findings_pass_<N>` (Step 6) — JSON array of the filtered findings, used for cross-pass de-duplication

All updates use the same `TMP=$STATE_FILE.tmp; jq ... > "$TMP" && mv "$TMP" "$STATE_FILE"` pattern.
