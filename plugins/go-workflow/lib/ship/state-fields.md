# Ship — State File Fields

Loaded by `skills/ship/SKILL.md` Step 1 when persisting initial arguments.
Owns initialization of the resolved ship workflow object and its field-name
reference. Standalone ship uses the root path `[]`; embedded ship uses its
caller-owned child path.

## Step 1 Initial Persist

```bash
initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"

if [ -z "$(get_loop_field "$STATE_FILE" "pass" "$WORKFLOW_STATE_PATH")" ]; then
  set_loop_field "$STATE_FILE" "args" "$ARGUMENTS" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "llm" "$LLM_CHOICE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "llm_explicit" "$LLM_EXPLICIT" "$WORKFLOW_STATE_PATH"
  set_loop_json_field "$STATE_FILE" "pass" 0 "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "no_merge" "$NO_MERGE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "pr_number" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "base_branch" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "bot_review_baseline" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "discovered_bots" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "has_ci" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "ci_skip_reason" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "skip_coverage" "$SKIP_COVERAGE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "coverage_threshold" "$COVERAGE_THRESHOLD" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "coverage_result" "" "$WORKFLOW_STATE_PATH"
  set_loop_json_field "$STATE_FILE" "coverage_tests_generated" 0 "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "e2e_required" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "e2e_attempted" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "e2e_result" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "e2e_skip_reason" "" "$WORKFLOW_STATE_PATH"
  set_loop_json_field "$STATE_FILE" "e2e_pages_tested" 0 "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_clean" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_result" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "review_skip_reason" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "head_sha" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "gemini_tier" "$GEMINI_TIER" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "ollama_model" "" "$WORKFLOW_STATE_PATH"
fi

if [ "$SHIP_EMBEDDED" != "true" ]; then
  set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
  set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH" '[]'
  set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
fi
```

## Field Reference

Each field is read on stop-hook re-entry (Step 2). Don't rename — phase
routing and subsequent steps depend on these exact names.

| Field | Type | Set by | Meaning |
|-------|------|--------|---------|
| `args` | string | Step 1 | Original `$ARGUMENTS` for re-parsing on re-entry |
| `llm` | string | Step 1 | `codex` / `gemini` / `ollama` |
| `llm_explicit` | string | Step 1 | `"true"` only when the invocation explicitly selected `--llm`; protects user backend intent |
| `pass` | int | Step 8 | Current LLM review pass; incremented after each commit cycle |
| `no_merge` | string | Step 1 | `"true"` if `--no-merge` was passed |
| `pr_number` | string | Step 9b | PR number after creation (empty pre-push) |
| `base_branch` | string | Step 3 | The PR's base branch |
| `bot_review_baseline` | ISO timestamp | Step 9c, 12c | Captured BEFORE push to catch fast bot responses |
| `discovered_bots` | comma-separated string | Step 11a | Bot logins matched against the registry |
| `has_ci` | string | Step 10 | `"true"` when checks register; `"false"` when no workflow applies |
| `ci_skip_reason` | string | Step 10 | Empty when CI applies; otherwise `"no-workflow-files"` or `"no-applicable-workflow"` |
| `skip_coverage` | string | Step 1 | Compatibility hint; never waives changed-source coverage |
| `coverage_threshold` | string | Step 1 | Default `"60"` |
| `coverage_result` | string | Step E.3 of coverage-verification.md | Aggregate percent, or empty when skipped |
| `coverage_skip_reason` | string | Step E.3 of coverage-verification.md | Empty when computed; `"all-main"` when every changed file was `package main` |
| `coverage_tests_generated` | int | Step F of coverage-verification.md | Count of new tests created |
| `e2e_required` | string | Step 7.6 | `"true"` when the diff is UI-visible and browser E2E is required |
| `e2e_attempted` | string | Step 7.6e | `"true"` after the first browser tool call is issued, even when that call fails |
| `e2e_result` | string | Step 7.6e | `"passed"` / `"blocked"` / `"skipped"`; `blocked` means required E2E did not pass and merge must stop |
| `e2e_skip_reason` | string | Step 7.6e | Empty on pass; otherwise machine-readable reason such as `"no-ui-visible-changes"`, `"missing-browser-tooling"`, `"browser-tool-call-failed"`, or `"dev-server-unavailable"` |
| `e2e_pages_tested` | int | Step 7.6e | Number of routes tested |
| `review_clean` | string | Step 5c | `"true"` when LLM returned no findings — fast-path past Step 6 on re-entry |
| `review_result` | string | Step 2 recovery, Step 5 | `"void"` when a prior session's review expired or `"skipped"` when a headless worker cannot run it synchronously |
| `review_skip_reason` | string | Step 2 recovery, Step 5 | `"session-boundary"` or `"headless-worker"` when no local agent review result is used |
| `head_sha` | string | Step 9c, 10e, 12c | Latest pushed commit; CI watch is anchored to this |
| `gemini_tier` | string | Step 1 | `flex`/`standard`/`priority` (gemini only; warning rendered at review time) |
| `ollama_model` | string | Step 5b | Installed Ollama model selected once and reused for every review pass |
| `workflow_result` | string | Hard invariant failure | `"incomplete"` when an invariant stops the workflow |
| `workflow_reason` | string | Hard invariant failure | Machine-readable hard-stop reason |
| `llm_check_failed` | string | Step 4b | `"true"` after diagnostic; cleared on Retry success |
| `use_agent_review` | string | Step 4b | `"true"` when the driver selected agent-based review for an unpinned backend or the user authorized replacing a pinned backend |
| `quick_mode` | string | Step 5b | `"true"` when the driver selected `codex review --base` after evidence showed exhaustive mode could not complete |
| `awaiting_driver_input` | boolean | Driver interaction rules | `true` while the workflow is paused for missing intent |
| `driver_input_reason` | string | Driver interaction rules | Missing intent recorded while the loop is paused |
