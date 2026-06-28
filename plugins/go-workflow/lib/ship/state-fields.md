# Ship — State File Fields

Loaded by `skills/ship/SKILL.md` Step 1 when persisting initial arguments.
Owns the full `jq` invocation and field-name reference.

## Step 1 Initial Persist

```bash
STATE_FILE=".local/state/ship.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg args "$ARGUMENTS" --arg llm "$LLM_CHOICE" --argjson pass 0 \
   --arg no_merge "$NO_MERGE" --arg pr_number "" --arg base_branch "" \
   --arg bot_review_baseline "" --arg discovered_bots "" --arg has_ci "" \
   --arg skip_coverage "$SKIP_COVERAGE" --arg coverage_threshold "$COVERAGE_THRESHOLD" \
   --arg coverage_result "" --argjson coverage_tests_generated 0 \
   --arg e2e_required "" --arg e2e_attempted "" --arg e2e_result "" \
   --arg e2e_skip_reason "" --argjson e2e_pages_tested 0 \
   --arg review_clean "" --arg head_sha "" --arg gemini_tier "$GEMINI_TIER" \
   '. + {args: $args, llm: $llm, pass: $pass, no_merge: $no_merge, pr_number: $pr_number, base_branch: $base_branch, bot_review_baseline: $bot_review_baseline, discovered_bots: $discovered_bots, has_ci: $has_ci, skip_coverage: $skip_coverage, coverage_threshold: $coverage_threshold, coverage_result: $coverage_result, coverage_tests_generated: $coverage_tests_generated, e2e_required: $e2e_required, e2e_attempted: $e2e_attempted, e2e_result: $e2e_result, e2e_skip_reason: $e2e_skip_reason, e2e_pages_tested: $e2e_pages_tested, review_clean: $review_clean, head_sha: $head_sha, gemini_tier: $gemini_tier}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Field Reference

Each field is read on stop-hook re-entry (Step 2). Don't rename — phase
routing and subsequent steps depend on these exact names.

| Field | Type | Set by | Meaning |
|-------|------|--------|---------|
| `args` | string | Step 1 | Original `$ARGUMENTS` for re-parsing on re-entry |
| `llm` | string | Step 1 | `codex` / `gemini` / `ollama` |
| `pass` | int | Step 8 | Current LLM review pass; incremented after each commit cycle |
| `no_merge` | string | Step 1 | `"true"` if `--no-merge` was passed |
| `pr_number` | string | Step 9b | PR number after creation (empty pre-push) |
| `base_branch` | string | Step 3 | The PR's base branch |
| `bot_review_baseline` | ISO timestamp | Step 9c, 12c | Captured BEFORE push to catch fast bot responses |
| `discovered_bots` | comma-separated string | Step 11a | Bot logins matched against the registry |
| `has_ci` | string | Step 10 | `"true"`/`"false"` — whether `.github/workflows/*.yml` exists |
| `skip_coverage` | string | Step 1 | `"true"` if `--skip-coverage` was passed |
| `coverage_threshold` | string | Step 1 | Default `"60"` |
| `coverage_result` | string | Step E.3 of coverage-verification.md | Aggregate percent, or empty when skipped |
| `coverage_skip_reason` | string | Step E.3 of coverage-verification.md | Empty when computed; `"all-main"` when every changed file was `package main` |
| `coverage_tests_generated` | int | Step F of coverage-verification.md | Count of new tests created |
| `e2e_required` | string | Step 7.6 | `"true"` when the diff is UI-visible and browser E2E is required |
| `e2e_attempted` | string | Step 7.6e | `"true"` when E2E ran |
| `e2e_result` | string | Step 7.6e | `"passed"` / `"blocked"` / `"skipped"`; `blocked` means required E2E did not pass and merge must stop |
| `e2e_skip_reason` | string | Step 7.6e | Empty on pass; otherwise machine-readable reason such as `"no-ui-visible-changes"`, `"missing-browser-tooling"`, or `"dev-server-unavailable"` |
| `e2e_pages_tested` | int | Step 7.6e | Number of routes tested |
| `review_clean` | string | Step 5c | `"true"` when LLM returned no findings — fast-path past Step 6 on re-entry |
| `head_sha` | string | Step 9c, 10e, 12c | Latest pushed commit; CI watch is anchored to this |
| `gemini_tier` | string | Step 1 | `flex`/`standard`/`priority` (gemini only; warning rendered at review time) |
| `llm_check_failed` | string | Step 4b | `"true"` after diagnostic; cleared on Retry success |
| `use_agent_review` | string | Step 4b | `"true"` when user chose agent-based review fallback |
| `quick_mode` | string | Step 5b | `"true"` when user picked `codex review --base` after large-diff warning or timeout |
