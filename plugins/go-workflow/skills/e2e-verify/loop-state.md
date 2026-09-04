# E2E Verify — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry", Steps 1-2, and Step 5
when the agent needs to bootstrap the loop, persist field updates, or
re-enter mid-flow.

Standalone E2E uses the normalized absolute
`.local/state/e2e-verify-${PR_NUM}.loop.local.json` path resolved by SKILL.md.
Embedded E2E uses its caller's physical state file and component path. Field
names listed here are part of the contract with `pr-results-comment.md` and
`mode-finish.md` — do not rename them.

An unversioned E2E state in `ship`/`fix-and-ship` mode or the `shipping` phase
cannot identify its former separate ship loop. Re-entry fails closed without
mutation and directs the user to cancel and restart E2E verification. Other
single-workflow legacy E2E states migrate additively.

## Bootstrap Block

Run during "Loop Initialization & Re-entry". Detects re-entry and skips
`setup-loop.sh` when a phase already exists; otherwise creates the state file.

```bash
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  EXISTING_PHASE=$(get_loop_field "$STATE_FILE" "phase" "$WORKFLOW_STATE_PATH")
  echo "Embedded E2E state phase: ${EXISTING_PHASE:-<none>}"
elif [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  EXISTING_PHASE="$PHASE"
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ] || [ -n "${EXISTING_PHASE:-}" ]; then
  PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  PERSISTED_WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
  REGISTERED_WORKTREES=$(git -C "$RESOLVED_ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$RESOLVED_ORIGINAL_REPO_ROOT" ] ||
     [ -z "$PERSISTED_WORKTREE_PATH" ] ||
     [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
     [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit found ? 0 : 1 }' ||
     [ -z "$PERSISTED_REPO_SLUG" ] ||
     [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
    WORKFLOW_REASON=e2e-worktree-path-invalid
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
      echo "E2E_VERIFY_RESULT=incomplete"
      echo "E2E_VERIFY_REASON=$WORKFLOW_REASON"
    else
      set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
      echo "<done>INCOMPLETE</done>"
    fi
    exit 1
  fi
  ORIGINAL_REPO_ROOT="$PERSISTED_ORIGINAL_REPO_ROOT"
  WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
  REPO_SLUG="$PERSISTED_REPO_SLUG"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  echo "Embedded E2E is using the caller-owned loop state."
elif [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "e2e-verify-${PR_NUM}" "VERIFIED" 30 "" \
    '{"rebasing":"Resume rebase onto base branch.","building":"Resume build verification.","addressing":"Resume address-review fixes from its component phase.","investigating":"Resume investigation.","e2e-testing":"Resume E2E tests. Restart dev server if needed.","posting":"Resume posting results to PR.","shipping":"Resume ship workflow from its component phase.","e2e-failed":"Report the persisted failure reason and stop."}' \
    "$STATE_FILE" '["VERIFIED","E2E_FAIL","INCOMPLETE"]'
fi
```

## Persist Arguments Block

Runs immediately after bootstrap so subsequent re-entries see the original
mode and PR number.

```bash
initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
if [ -z "$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')" ]; then
  set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
fi
if [ -z "$(get_loop_field "$STATE_FILE" "worktree_path" '[]')" ]; then
  set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH" '[]'
fi
if [ -z "$(get_loop_field "$STATE_FILE" "repo_slug" '[]')" ]; then
  set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
fi
set_loop_field "$STATE_FILE" "mode" "$MODE" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "pr_number" "$PR_NUM" "$WORKFLOW_STATE_PATH"
if [ -z "$(get_loop_field "$STATE_FILE" "build_result" "$WORKFLOW_STATE_PATH")" ]; then
  set_loop_field "$STATE_FILE" "build_result" "" "$WORKFLOW_STATE_PATH"
fi
if [ -z "$(get_loop_field "$STATE_FILE" "e2e_result" "$WORKFLOW_STATE_PATH")" ]; then
  set_loop_field "$STATE_FILE" "e2e_result" "" "$WORKFLOW_STATE_PATH"
fi
if [ -z "$(get_loop_field "$STATE_FILE" "pages_tested" "$WORKFLOW_STATE_PATH")" ]; then
  set_loop_json_field "$STATE_FILE" "pages_tested" 0 "$WORKFLOW_STATE_PATH"
fi
for INITIAL_FIELD in build_result e2e_result base_branch workflow_result workflow_reason generation_target generated_commit_status generated_commit_parent generated_commit_sha; do
  if [ -z "$(get_loop_field "$STATE_FILE" "$INITIAL_FIELD" "$WORKFLOW_STATE_PATH")" ]; then
    set_loop_field "$STATE_FILE" "$INITIAL_FIELD" "" "$WORKFLOW_STATE_PATH"
  fi
done
for INITIAL_JSON_FIELD in generation_snapshot generated_files; do
  if [ -z "$(get_loop_field "$STATE_FILE" "$INITIAL_JSON_FIELD" "$WORKFLOW_STATE_PATH")" ]; then
    set_loop_json_field "$STATE_FILE" "$INITIAL_JSON_FIELD" '[]' "$WORKFLOW_STATE_PATH"
  fi
done
```

## Re-entry Check

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  E2E_STATE_JSON=$(jq -c --argjson path "$WORKFLOW_STATE_PATH" 'getpath($path)' "$STATE_FILE")
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
  set_loop_field "$STATE_FILE" "workflow_result" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "workflow_reason" "" "$WORKFLOW_STATE_PATH"
  if [ "$EMBEDDED_WORKFLOW" != "true" ]; then
    set_loop_completion_promise "$STATE_FILE" "VERIFIED"
  fi
  set_loop_phase "$STATE_FILE" "addressing" "$WORKFLOW_STATE_PATH"
  PHASE=addressing
fi
```

If `PHASE` is set (non-empty), this is a re-entry. Recover state from
persisted fields, including the exact `GEN_NEW_FILES` array when re-entering
the `addressing` phase, and skip to the corresponding phase listed in the
SKILL.md phase routing table. If `PHASE` is empty, this is a fresh start —
continue to Step 1.

## Terminal Re-entry

Run immediately after the re-entry check. A terminal E2E failure reports its
persisted reason, re-emits only its terminal promise, and stops:

```bash
if [ "$PHASE" = "e2e-failed" ]; then
  WORKFLOW_REASON=$(get_loop_field "$STATE_FILE" "reason" "$WORKFLOW_STATE_PATH")
  echo "E2E verification failed: $WORKFLOW_REASON"
  if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
    echo "E2E_VERIFY_RESULT=e2e-fail"
    echo "E2E_VERIFY_REASON=$WORKFLOW_REASON"
  else
    echo "<done>E2E_FAIL</done>"
  fi
  exit 0
fi
```

## Persist Build Result (Steps 1-2)

```bash
set_loop_phase "$STATE_FILE" "building" "$WORKFLOW_STATE_PATH"
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
set_loop_field "$STATE_FILE" "build_result" "$BUILD_RESULT" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "base_branch" "$BASE_BRANCH" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "generation_target" "${GEN_TARGET:-}" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "generation_snapshot" "$GENERATION_SNAPSHOT_JSON" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "generated_files" "$GENERATED_FILES_JSON" "$WORKFLOW_STATE_PATH"
```

## Persist E2E Result (Step 5)

```bash
set_loop_field "$STATE_FILE" "e2e_result" "$E2E_RESULT" "$WORKFLOW_STATE_PATH"
set_loop_json_field "$STATE_FILE" "pages_tested" "$PAGES_TESTED" "$WORKFLOW_STATE_PATH"
```
