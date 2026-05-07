# Review Loop — Parse Findings (Step 6)

Loaded by `commands/review-loop.md` Step 6. Two paths: structured JSON (codex
exec mode) and free-text (codex quick / gemini / ollama).

## Structured JSON Path (codex exec mode)

Active when `LLM_CHOICE == codex` AND `QUICK_MODE != true` AND
`CODEX_EXEC_FALLBACK != true`.

### 1. Validate JSON

```bash
printf '%s\n' "$REVIEW_JSON" | jq empty 2>/dev/null
```

If invalid, log a warning and fall through to the free-text path with `FINDINGS="$REVIEW_JSON"`.

### 2. Extract overall fields

```bash
OVERALL=$(printf '%s\n' "$REVIEW_JSON" | jq -r '.overall_correctness')
OVERALL_EXPLANATION=$(printf '%s\n' "$REVIEW_JSON" | jq -r '.overall_explanation')
OVERALL_CONFIDENCE=$(printf '%s\n' "$REVIEW_JSON" | jq -r '.overall_confidence_score')
```

### 3. Filter low-confidence FIRST

Discard findings with `confidence_score < 0.3` BEFORE checking for clean
review (so filtered-to-zero also triggers the clean path):

```bash
FILTERED_JSON=$(printf '%s\n' "$REVIEW_JSON" | jq '{
  findings: [.findings[] | select(.confidence_score >= 0.3)],
  overall_correctness: .overall_correctness,
  overall_explanation: .overall_explanation,
  overall_confidence_score: .overall_confidence_score
}')
FINDING_COUNT=$(printf '%s\n' "$FILTERED_JSON" | jq '.findings | length')
```

### 4. Check for clean review AFTER filtering

If `FINDING_COUNT == 0` and `OVERALL == "patch is correct"`:

- If `PASS == 1`: ask user to confirm scope. If confirmed → output `<done>REVIEW_CLEAN</done>`.
- If `PASS > 1`: clean verification pass. Output summary and `<done>REVIEW_CLEAN</done>`.

If `FINDING_COUNT == 0` but `OVERALL == "patch is incorrect"`: display
`overall_explanation` as a warning, but treat as clean (no actionable
findings survived filtering).

### 5. Sort by priority then confidence

`priority` ascending (0 first), then `confidence_score` descending.

### 6. Display formatted table

```
## Review Findings (Pass $PASS) — $FINDING_COUNT issues

| # | Priority | Category | File | Lines | Title | Confidence |
|---|----------|----------|------|-------|-------|------------|
| 1 | P0 | correctness | api/handler.go | 42-45 | Nil pointer on empty response | 0.95 |
```

Display `overall_explanation` as a summary below the table.

### 7. De-duplicate across passes

Compare `(file_path, line_range.start, normalized title)` against previous-pass
findings stored in the state file. Skip duplicates.

### 8. Persist findings to state file

```bash
jq --argjson f "$FILTERED_JSON" --arg key "findings_pass_$PASS" \
  '.[$key] = $f.findings' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Free-text Path (codex quick / gemini / ollama)

After capturing the LLM review output as `FINDINGS`:

- If output (trimmed) equals exactly `NO_ISSUES_FOUND` or has fewer than 20 characters of content:
  - If `PASS == 1`: ask user to confirm the scope is correct (first-pass clean review may indicate wrong scope). If user confirms → output `<done>REVIEW_CLEAN</done>` and stop.
  - If `PASS > 1`: clean review after fixes. Output summary and `<done>REVIEW_CLEAN</done>`.
- Otherwise: extract structured findings from the output. Display findings to user with pass number.

## Bot Noise Filter (both paths)

Silently discard any finding whose body contains usage-limit / quota messages:

- "reached your Codex usage limits"
- "usage limits for code reviews"
- "see your limits"

These are external-service messages, never blockers.
