# E2E Verify — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry", Steps 1-2, and Step 5
when the agent needs to bootstrap the loop, persist field updates, or
re-enter mid-flow.

The state file path is always absolute beneath `ORIGINAL_REPO_ROOT`, never
relative to an ambient directory. Field names listed
here are part of the contract with `pr-results-comment.md` and
`mode-finish.md` — do not rename them.

## Bootstrap Block

Run during "Loop Initialization & Re-entry". Detects re-entry and skips
`setup-loop.sh` when a phase already exists; otherwise creates the state file.

```bash
STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/e2e-verify-${PR_NUM}.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    PERSISTED_ORIGINAL_REPO_ROOT=$(jq -r '.original_repo_root // empty' "$STATE_FILE" 2>/dev/null || true)
    PERSISTED_WORKTREE_PATH=$(jq -r '.worktree_path // empty' "$STATE_FILE" 2>/dev/null || true)
    PERSISTED_REPO_SLUG=$(jq -r '.repo_slug // empty' "$STATE_FILE" 2>/dev/null || true)
    REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')
    if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
       [ -z "$PERSISTED_WORKTREE_PATH" ] ||
       [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
       [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
       ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit !found }' ||
       [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
      TMP="${STATE_FILE}.tmp"
      jq '.workflow_result = "incomplete" | .workflow_reason = "e2e-worktree-path-invalid" | .phase = "incomplete" | .completion_promise = "INCOMPLETE"' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
      echo "WORKFLOW_RESULT=INCOMPLETE"
      echo "WORKFLOW_REASON=e2e-worktree-path-invalid"
      echo "<done>INCOMPLETE</done>"
      exit 1
    fi
    WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
    REPO_SLUG="$PERSISTED_REPO_SLUG"
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi

if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "e2e-verify-${PR_NUM}" "VERIFIED" 30 "" \
    '{"rebasing":"Resume rebase onto base branch.","building":"Resume build verification.","addressing":"Resume address-review fixes.","investigating":"Resume investigation.","e2e-testing":"Resume E2E tests. Restart dev server if needed.","posting":"Resume posting results to PR.","shipping":"Resume ship workflow."}' \
    "$STATE_FILE"
fi
```

## Persist Arguments Block

Runs immediately after bootstrap so subsequent re-entries see the original
mode and PR number.

```bash
TMP="${STATE_FILE}.tmp"
jq --arg mode "$MODE" --arg pr_number "$PR_NUM" --arg build_result "" \
   --arg e2e_result "" --argjson pages_tested 0 --arg base_branch "" \
   --arg workflow_result "" --arg workflow_reason "" --arg original_repo_root "$ORIGINAL_REPO_ROOT" \
   --arg worktree_path "$WORKTREE_PATH" --arg repo_slug "$REPO_SLUG" \
   --arg generation_target "" --argjson generation_snapshot '[]' \
   --arg generated_commit_status "" --arg generated_commit_parent "" \
   --arg generated_commit_sha "" \
   --argjson generated_files '[]' \
   '. + {mode: $mode, pr_number: $pr_number, build_result: $build_result, e2e_result: $e2e_result, pages_tested: $pages_tested, base_branch: $base_branch, workflow_result: $workflow_result, workflow_reason: $workflow_reason, original_repo_root: (if (.original_repo_root // "") == "" then $original_repo_root else .original_repo_root end), worktree_path: (if (.worktree_path // "") == "" then $worktree_path else .worktree_path end), repo_slug: (if (.repo_slug // "") == "" then $repo_slug else .repo_slug end), generation_target: (.generation_target // $generation_target), generation_snapshot: (.generation_snapshot // $generation_snapshot), generated_files: (.generated_files // $generated_files), generated_commit_status: (.generated_commit_status // $generated_commit_status), generated_commit_parent: (.generated_commit_parent // $generated_commit_parent), generated_commit_sha: (.generated_commit_sha // $generated_commit_sha)}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
  E2E_STATE_JSON=$(cat "$STATE_FILE")
  GEN_TARGET=$(jq -r '.generation_target // empty' <<< "$E2E_STATE_JSON")
  GEN_SNAPSHOT_FILES=()
  while IFS= read -r -d '' SNAPSHOT_FILE; do
    GEN_SNAPSHOT_FILES+=("$SNAPSHOT_FILE")
  done < <(jq -j 'if ((.generation_snapshot // []) | type) == "array" then .generation_snapshot[]? else ((.generation_snapshot // "") | split("\n")[] | select(length > 0)) end | ., "\u0000"' <<< "$E2E_STATE_JSON")
  GENERATED_COMMIT_STATUS=$(jq -r '.generated_commit_status // empty' <<< "$E2E_STATE_JSON")
  GENERATED_COMMIT_PARENT=$(jq -r '.generated_commit_parent // empty' <<< "$E2E_STATE_JSON")
  GENERATED_COMMIT_SHA=$(jq -r '.generated_commit_sha // empty' <<< "$E2E_STATE_JSON")
  GEN_NEW_FILES=()
  while IFS= read -r -d '' GENERATED_FILE; do
    GEN_NEW_FILES+=("$GENERATED_FILE")
  done < <(jq -j '.generated_files[]? | ., "\u0000"' <<< "$E2E_STATE_JSON")
fi
```

If `PHASE=incomplete` and `GENERATED_COMMIT_STATUS` is `committing` or
`push-pending`, the generated-output transaction is recoverable. Clear the
incomplete outcome, restore the normal completion promise, set phase to
`addressing`, and resume Step 3 so it can reconcile the exact persisted
transaction before invoking address-review:

```bash
if [ "${PHASE:-}" = "incomplete" ] &&
   { [ "${GENERATED_COMMIT_STATUS:-}" = "committing" ] ||
     [ "${GENERATED_COMMIT_STATUS:-}" = "push-pending" ]; }; then
  TMP="${STATE_FILE}.tmp"
  jq '.workflow_result = "" | .workflow_reason = "" | .completion_promise = "VERIFIED" | .phase = "addressing"' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
  PHASE=addressing
fi
```

If `PHASE` is set (non-empty), this is a re-entry. Recover state from
persisted fields, including the exact `GEN_NEW_FILES` array when re-entering
the `addressing` phase, and skip to the corresponding phase listed in the
SKILL.md phase routing table. If `PHASE` is empty, this is a fresh start —
continue to Step 1.

## Persist Build Result (Steps 1-2)

```bash
set_loop_phase "$STATE_FILE" "building"
if [ "${GEN_NEW_FILES[0]+set}" = "set" ]; then
  GENERATED_FILES_JSON=$(jq -cn '$ARGS.positional' --args "${GEN_NEW_FILES[@]}")
else
  GENERATED_FILES_JSON='[]'
fi
if [ "${GEN_SNAPSHOT_FILES[0]+set}" = "set" ]; then
  GENERATION_SNAPSHOT_JSON=$(jq -cn '$ARGS.positional' --args "${GEN_SNAPSHOT_FILES[@]}")
else
  GENERATION_SNAPSHOT_JSON='[]'
fi
TMP="${STATE_FILE}.tmp"
jq --arg build_result "$BUILD_RESULT" --arg base_branch "$BASE_BRANCH" \
   --arg generation_target "${GEN_TARGET:-}" \
   --argjson generation_snapshot "$GENERATION_SNAPSHOT_JSON" \
   --argjson generated_files "$GENERATED_FILES_JSON" \
   '.build_result = $build_result | .base_branch = $base_branch | .generation_target = $generation_target | .generation_snapshot = $generation_snapshot | .generated_files = $generated_files' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Persist E2E Result (Step 5)

```bash
TMP="${STATE_FILE}.tmp"
jq --arg e2e_result "$E2E_RESULT" --argjson pages_tested "$PAGES_TESTED" \
   '.e2e_result = $e2e_result | .pages_tested = $pages_tested' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```
