# E2E Verify — Loop State Plumbing

Loaded by `SKILL.md` "Loop Initialization & Re-entry", Steps 1-2, and Step 5
when the agent needs to bootstrap the loop, persist field updates, or
re-enter mid-flow.

The state file path is always `.local/state/e2e-verify-${PR_NUM}.loop.local.json`
relative to the original repo directory (not a worktree). Field names listed
here are part of the contract with `pr-results-comment.md` and
`mode-finish.md` — do not rename them.

## Bootstrap Block

Run during "Loop Initialization & Re-entry". Detects re-entry and skips
`setup-loop.sh` when a phase already exists; otherwise creates the state file.

```bash
STATE_FILE=".local/state/e2e-verify-${PR_NUM}.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi

if [ -f "$STATE_FILE" ] && [ -n "$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "e2e-verify-${PR_NUM}" "VERIFIED" 30 "" \
    '{"rebasing":"Resume rebase onto base branch.","building":"Resume build verification.","addressing":"Resume address-review fixes.","investigating":"Resume investigation.","e2e-testing":"Resume E2E tests. Restart dev server if needed.","posting":"Resume posting results to PR.","shipping":"Resume ship workflow."}'
fi
```

## Persist Arguments Block

Runs immediately after bootstrap so subsequent re-entries see the original
mode and PR number.

```bash
STATE_FILE=".local/state/e2e-verify-${PR_NUM}.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg mode "$MODE" --arg pr_number "$PR_NUM" --arg build_result "" \
   --arg e2e_result "" --argjson pages_tested 0 --arg base_branch "" \
   '. + {mode: $mode, pr_number: $pr_number, build_result: $build_result, e2e_result: $e2e_result, pages_tested: $pages_tested, base_branch: $base_branch}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry. Recover state from
persisted fields and skip to the corresponding phase listed in the SKILL.md
phase routing table. If `PHASE` is empty, this is a fresh start — continue
to Step 1.

## Persist Build Result (Steps 1-2)

```bash
set_loop_phase "$STATE_FILE" "building"
TMP="$STATE_FILE.tmp"
jq --arg build_result "$BUILD_RESULT" --arg base_branch "$BASE_BRANCH" \
   '.build_result = $build_result | .base_branch = $base_branch' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## Persist E2E Result (Step 5)

```bash
TMP="$STATE_FILE.tmp"
jq --arg e2e_result "$E2E_RESULT" --argjson pages_tested "$PAGES_TESTED" \
   '.e2e_result = $e2e_result | .pages_tested = $pages_tested' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```
