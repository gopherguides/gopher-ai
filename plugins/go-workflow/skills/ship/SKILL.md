---
name: ship
description: "Ship a PR end-to-end: verify locally, push, create/update the PR, watch CI, handle review feedback, and merge without admin override. Use for 'ship', 'ship it', or 'push and merge'. SKIP if the user only wants a PR opened; use `create-pr`."
argument-hint: "[--llm codex|gemini|ollama|fable] [--passes <n>] [--no-merge] [--skip-coverage] [--coverage-threshold <n>] [--tier flex|standard|priority]"
disable-model-invocation: true
---

# Ship PR

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before requesting decisions or delegating work, read
`<PLUGIN_ROOT>/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving any workflow
choice.

Bind the invocation arguments as `SKILL_ARGS` for `$go-workflow:ship` by
reading `<PLUGIN_ROOT>/lib/skill-arguments.md` with this Claude Code compatibility payload:
<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

Load the shared GitHub REST helpers before any GitHub workflow operation:

```bash
source "<PLUGIN_ROOT>/lib/github-rest.sh"
```

## GraphQL Budget Discipline (read first)

GitHub meters **two separate** hourly budgets: ~5,000 **GraphQL points/hr** and
~5,000 **REST requests/hr**. Tools that drive a GitHub Project board (e.g.
Detent) already spend the GraphQL budget on ProjectV2 polling (Projects v2 is
GraphQL-only). If this skill *also* leans on GraphQL for routine PR ops, the two
collide and exhaust the shared pool — a CI-watch loop alone can burn hundreds of
GraphQL points per PR. Keep routine PR work on the REST budget through the
shared helper:

- **CI status / watch:** use `github_watch_pr_checks` or
  `github_check_snapshot`, always pinned to the expected PR head SHA.
- **PR metadata:** use `github_current_pr` and `github_pr`.
- **Formal reviews:** use `github_pr_reviews`.
- **Mergeability:** read REST `.mergeable` and `.mergeable_state` through
  `github_pr`.
- **Ordinary merge:** use the REST pull merge endpoint with `merge_method` and
  the expected head SHA.

The only GraphQL exceptions in these workflows are review-thread discovery and
resolution, `closingIssuesReferences`, and required merge-queue enqueueing.
The sibling `e2e-verify`, `address-review`, and `complete-issue` skills source
the same shared helper and follow this discipline.

## 0. State File Bootstrap

Ship has exactly one state owner. A caller embeds ship by supplying both
`CALLER_LOOP_STATE_FILE` and `CALLER_WORKFLOW_STATE_PATH`; ship creates a child
object in that physical file and never initializes another loop. Without both
values, ship is standalone and always resolves the released canonical state
file under the original repository root. A valid legacy standalone file is
migrated in place by `read_loop_state`, preserving its root field names and
phase routing.

Released ship versions could write that standalone file under a linked
worktree. When the canonical primary-root file is absent, ship enumerates the
linked worktree's loop-state files and relocates the candidate only when exactly
one exists and it is valid ship state. It then migrates the schema and fills
only missing root locator fields from the current registered worktree. Multiple
linked candidates, invalid JSON, or state owned by another loop stop without
mutation and name every ambiguous path. An existing canonical state always
wins; linked-worktree strays are ignored in that case.

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"

SHIP_EMBEDDED=false
WORKFLOW_STATE_PATH='[]'

if [ -n "${CALLER_LOOP_STATE_FILE:-}" ] || [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  if [ -z "${CALLER_LOOP_STATE_FILE:-}" ] || [ -z "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
    echo "ERROR: Embedded ship requires both caller state file and workflow path."
    exit 1
  fi
  case "$CALLER_LOOP_STATE_FILE" in
    /*) ;;
    *) echo "ERROR: Embedded ship caller state file must be absolute."; exit 1 ;;
  esac
  if [ ! -f "$CALLER_LOOP_STATE_FILE" ] ||
     ! jq -e '.schema_version == 2' "$CALLER_LOOP_STATE_FILE" >/dev/null 2>&1; then
    echo "ERROR: Embedded ship requires an existing v2 caller state file."
    exit 1
  fi

  STATE_FILE="$CALLER_LOOP_STATE_FILE"
  WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "ship")
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  SHIP_EMBEDDED=true
  ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
else
  CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
  ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
  WORKTREE_PATH="${WORKTREE_PATH:-$CURRENT_CHECKOUT_ROOT}"
  if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] ||
     [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
    echo "ERROR: Could not resolve absolute repository paths."
    exit 1
  fi

  CANONICAL_STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/ship.loop.local.json"
  STATE_FILE="$CANONICAL_STATE_FILE"
  CURRENT_REPO_SLUG=$(cd "$WORKTREE_PATH" && gh api "repos/{owner}/{repo}" --jq '.full_name')
  MIGRATED_LINKED_STATE=false

  if [ ! -f "$CANONICAL_STATE_FILE" ] &&
     [ "$CURRENT_CHECKOUT_ROOT" != "$ORIGINAL_REPO_ROOT" ]; then
    LINKED_STATE_CANDIDATES=()
    for LINKED_STATE_CANDIDATE in "$CURRENT_CHECKOUT_ROOT/.local/state/"*.loop.local.json; do
      [ -f "$LINKED_STATE_CANDIDATE" ] || continue
      LINKED_STATE_CANDIDATES+=("$LINKED_STATE_CANDIDATE")
    done
    if [ "${#LINKED_STATE_CANDIDATES[@]}" -gt 1 ]; then
      echo "ERROR: Ambiguous linked-worktree loop state candidates while canonical ship state '$CANONICAL_STATE_FILE' is absent; refusing migration:"
      printf ' - %s\n' "${LINKED_STATE_CANDIDATES[@]}"
      exit 1
    elif [ "${#LINKED_STATE_CANDIDATES[@]}" -eq 1 ]; then
      LEGACY_STATE_FILE="${LINKED_STATE_CANDIDATES[0]}"
      if ! jq -e '
        type == "object" and
        (.schema_version == null) and
        .loop_name == "ship" and
        (.completion_promise == "SHIPPED" or .completion_promise == "INCOMPLETE")
      ' "$LEGACY_STATE_FILE" >/dev/null 2>&1; then
        echo "ERROR: Invalid linked-worktree legacy ship state '$LEGACY_STATE_FILE': expected released unversioned ship JSON with a SHIPPED or INCOMPLETE promise; refusing migration to '$CANONICAL_STATE_FILE'."
        exit 1
      fi
      mkdir -p "$(dirname "$CANONICAL_STATE_FILE")"
      mv "$LEGACY_STATE_FILE" "$CANONICAL_STATE_FILE"
      MIGRATED_LINKED_STATE=true
      echo "Migrated linked-worktree ship state from '$LEGACY_STATE_FILE' to '$CANONICAL_STATE_FILE'."
    fi
  fi

  EXISTING_PHASE=""
  if [ -f "$STATE_FILE" ]; then
    read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
    if [ "$MIGRATED_LINKED_STATE" = "true" ]; then
      if [ -z "$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')" ]; then
        set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
      fi
      if [ -z "$(get_loop_field "$STATE_FILE" "worktree_path" '[]')" ]; then
        set_loop_field "$STATE_FILE" "worktree_path" "$CURRENT_CHECKOUT_ROOT" '[]'
      fi
      if [ -z "$(get_loop_field "$STATE_FILE" "repo_slug" '[]')" ]; then
        set_loop_field "$STATE_FILE" "repo_slug" "$CURRENT_REPO_SLUG" '[]'
      fi
      read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
    fi
    EXISTING_PHASE="$PHASE"
  fi

  if [ -n "$EXISTING_PHASE" ]; then
    PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" "$WORKFLOW_STATE_PATH")
    PERSISTED_WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" "$WORKFLOW_STATE_PATH")
    PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" "$WORKFLOW_STATE_PATH")
    REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')
    if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
       [ -z "$PERSISTED_WORKTREE_PATH" ] ||
       [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
       [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
       ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit !found }' ||
       [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
      set_loop_terminal_result "$STATE_FILE" "incomplete" "ship-worktree-path-invalid" "incomplete" "INCOMPLETE"
      echo "WORKFLOW_RESULT=INCOMPLETE"
      echo "WORKFLOW_REASON=ship-worktree-path-invalid"
      echo "<done>INCOMPLETE</done>"
      exit 1
    fi
    WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
    REPO_SLUG="$PERSISTED_REPO_SLUG"
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  else
    REPO_SLUG="${REPO_SLUG:-$CURRENT_REPO_SLUG}"
  fi

  if [ -z "$EXISTING_PHASE" ]; then
    if [ ! -x "<PLUGIN_ROOT>/scripts/setup-loop.sh" ]; then
      echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."
      exit 1
    fi
    /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" \
      "$(jq -c . "<PLUGIN_ROOT>/lib/ship/resume-messages.json")" \
      "$STATE_FILE" "[\"SHIPPED\",\"INCOMPLETE\"]"
  fi
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
fi
```

## 1. Parse Arguments

Parse `SKILL_ARGS` to extract:

- `--llm <value>`: `codex` (default), `gemini`, `ollama`, `fable` (Claude subagent — no external CLI; prefer when the diff was written by Codex so a different model family reviews it)
- `--passes <n>`: max LLM review passes (default: 3)
- `--no-merge`: stop after bot approval, don't auto-merge
- `--skip-coverage`: compatibility hint for source-free changes. Changed source
  files always run the coverage gate. E2E may be reused only when a prior
  `$go-workflow:e2e-verify` pass is recorded.
- `--coverage-threshold <n>`: override the default 60% threshold
- `--tier <value>`: gemini service tier (`flex`/`standard`/`priority`; gemini only; default: unset)

Store as `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`, `SKIP_COVERAGE`,
`COVERAGE_THRESHOLD` (default `60`), `GEMINI_TIER`, and `LLM_EXPLICIT`.
`LLM_EXPLICIT=true` only when `SKILL_ARGS` contains `--llm`; otherwise it is
`false`.

Persist arguments to the resolved workflow object so the
stop-hook can recover all fields on re-entry. The path-aware initialization lives in
`<PLUGIN_ROOT>/lib/ship/state-fields.md` — fields written: `args`,
`llm`, `pass`, `no_merge`, `pr_number`, `base_branch`,
`bot_review_baseline`, `discovered_bots`, `has_ci`, `ci_skip_reason`, `skip_coverage`,
`coverage_threshold`, `coverage_result`, `coverage_tests_generated`,
`e2e_required`, `e2e_attempted`, `e2e_result`, `e2e_skip_reason`,
`e2e_pages_tested`, `review_clean`, `review_result`,
`review_skip_reason`, `head_sha`, `gemini_tier`, `llm_explicit`.
For Ollama reviews, Step 5 also persists `ollama_model` after resolving it from
the installed model list.

## Hard Invariant Failure

When this skill or a supporting file says to stop incomplete, set the supplied
reason code as `WORKFLOW_REASON`, then persist the machine-readable outcome:

```bash
WORKFLOW_REASON="${WORKFLOW_REASON:?workflow reason is required}"
if [ "$SHIP_EMBEDDED" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
else
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
  echo "WORKFLOW_RESULT=INCOMPLETE"
  echo "WORKFLOW_REASON=$WORKFLOW_REASON"
  echo "<done>INCOMPLETE</done>"
fi
```

Stop the ship workflow after this block. Embedded ship returns the structured
result to its caller without changing caller-owned terminal fields or emitting
a marker. Standalone ship emits its allowlisted `INCOMPLETE` marker. Never ask
for permission to bypass the invariant and never output `SHIPPED` on this path.

## 2. Re-entry Check

```bash
[ -f "$STATE_FILE" ] && read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
```

If `PHASE` is set (non-empty), this is a stop-hook re-entry. Restore every Step
1 field through `get_loop_field "$STATE_FILE" "<field>"
"$WORKFLOW_STATE_PATH"`. If `review_clean == "true"`, set
`REVIEW_CLEAN=true` to preserve the clean-review fast path. Never read the
physical root directly because embedded ship owns only its child object.

An in-session review is never resumable. If `PHASE == "reviewing"` on
re-entry, the reviewer from the earlier session no longer exists. Do not wait
for it and do not dispatch a replacement. Follow **Expired review recovery**
below.

Then jump to the matching phase:

| Phase | Step |
|-------|------|
| `reviewing` | Expired review recovery, then Step 9 (Phase 2) |
| `review-required` | Step 5 (Phase 1) |
| `fixing` | Step 6 (Phase 1) |
| `verifying` | Step 7 (Phase 1) |
| `coverage-check` | Step 7.5 (Phase 1) |
| `e2e-testing` | Step 7.6 (Phase 1) |
| `pushing` | Step 9 (Phase 2) |
| `ci-watch` | Step 10 (Phase 3) |
| `bot-watching` | Step 11 (Phase 4) |
| `addressing` | Step 12 (Phase 5) |
| `merging` | Step 13 (Phase 6) |

If `PHASE` is empty/unset → fresh start. Continue to Step 3.

`review-required` is a durable request to start one review, used when CI
detects that the PR head changed. Step 5 immediately changes it to
`reviewing` before dispatch. This keeps a review that has not started distinct
from an in-flight review that expired at a session boundary.

### Expired review recovery

This path is for a successor session only. Treat the earlier review as void and
make the validated work durable before doing anything else:

1. Persist `review_result="void"` and
   `review_skip_reason="session-boundary"`. Never reuse a prior agent handle or
   review output.
2. If the index contains validated staged changes, inspect the staged diff and
   commit exactly those files with a conventional message that describes the
   change. Do not label this commit as review findings.
3. Set the phase to `pushing`, push every local commit, and ensure a non-draft
   PR exists via Step 9. Do all three in the same session before yielding.

If there is no staged diff, continue with the existing local commits. Unstaged
or untracked files were not part of the validated index; leave them untouched
and report them after the PR is open.

## 3. Detect Context

```bash
CURRENT_BRANCH=$(git -C "$WORKTREE_PATH" branch --show-current)
LOCAL_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)

if PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr "$CURRENT_BRANCH" "$LOCAL_HEAD_SHA"); then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.base.ref')
  echo "PR #$PR_NUM targets: $BASE_BRANCH"
else
  PR_LOOKUP_STATUS=$?
  if [ "$PR_LOOKUP_STATUS" -ne 4 ]; then
    WORKFLOW_REASON="current-pr-api-error"
  fi
  BASE_BRANCH=$(gh api "repos/$REPO_SLUG" --jq '.default_branch')
  PR_NUM=""
  echo "No PR found. Base: $BASE_BRANCH"
fi
```

An empty exact-head lookup returns status 4 and means no PR exists yet. Any
other lookup failure sets `WORKFLOW_REASON=current-pr-api-error`; follow
**Hard Invariant Failure** and stop rather than treating an API failure as no
PR.

**CRITICAL:** If `CURRENT_BRANCH == BASE_BRANCH`, set
`WORKFLOW_REASON=default-branch`, follow **Hard Invariant Failure**, and stop.
Do not ship from the default branch.

If `git -C "$WORKTREE_PATH" status --porcelain` shows uncommitted changes, resolve a
**driver-resolvable gate**. Inspect the diff, staged state, original request,
and workflow-owned file list:

- Include and commit changes only when they are unambiguously in scope and have
  fresh validation evidence.
- Preserve unrelated changes and ship only committed `HEAD` when later steps
  cannot overwrite or stage them.
- If ownership is ambiguous or safe isolation is impossible, stop incomplete
  with `WORKFLOW_REASON=unowned-worktree-changes`.

State `Decision`, `Evidence`, and `Rationale`; do not request input for this
technical ownership decision.

Persist the detected context in the resolved ship workflow object:

```bash
set_loop_field "$STATE_FILE" "base_branch" "$BASE_BRANCH" "$WORKFLOW_STATE_PATH"
set_loop_field "$STATE_FILE" "pr_number" "$PR_NUM" "$WORKFLOW_STATE_PATH"
```

## 4. Prerequisite Check

Verify the selected LLM CLI is installed. Read
`<PLUGIN_ROOT>/lib/ship/prerequisites.md` for the evidence-based
fallback ordering. A driver may replace an unpinned default and must state the
rationale. Replacing an explicitly selected backend is a missing-intent gate.

**On re-entry (Step 2):** Restore `USE_AGENT_REVIEW` and `LLM_EXPLICIT` from
state. If `use_agent_review=="true"`, set `CODEX_EXEC_FALLBACK=true`. If
`llm_check_failed=="true"` and no fallback is persisted, repeat the
prerequisite evidence check and its deterministic recovery policy.

---

## Phase 1: Local LLM Review (Steps 5–8)

LLM review → fix → verify → coverage gate (final pass) → E2E smoke (when
applicable) → commit → loop decision.

Delegated reviews are session-local: run them synchronously in the
foreground and wait for their final response. In a headless worker context,
skip an agent-backed review when it cannot finish within the current session;
persist the skip reason and proceed through commit, push, and non-draft PR
creation. Never end a session with staged or committed-but-unpushed work while
waiting on a background process.

**Coverage gate (Step 7.5, final pass only):** Read
`<PLUGIN_ROOT>/lib/coverage/coverage-verification.md` and follow
Steps A–F with `BASE_BRANCH=origin/${BASE_BRANCH}`, `STATE_FILE`,
`SKIP_COVERAGE`, `COVERAGE_THRESHOLD` from parsed args.

**Loop decision (Step 8):** clean review (`REVIEW_CLEAN=true`) OR
`PASS >= MAX_PASSES` → Phase 2. Otherwise → back to Step 5. Always stage only
fixed files (never `git add -A`).

→ Read `<PLUGIN_ROOT>/lib/ship/local-review.md` for: LLM execution
paths (codex exhaustive/quick, fable Claude-subagent, gemini, ollama,
agent-based fallback), structured-JSON vs free-text parsing,
`confidence_score < 0.3` filter, codegen-drift check
(Make targets `generate`, `gen`, `codegen`, `sqlc`, `proto`, or `templ`), E2E skip conditions, and the
staged-commit + pass-counter increment.

---

## Phase 2: Push and PR Creation (Step 9)

```bash
set_loop_phase "$STATE_FILE" "pushing" "$WORKFLOW_STATE_PATH"
```

Push to remote (use the configured tracking remote and PR `headRefName`), ensure
a PR exists (auto-detect template at `.github/pull_request_template.md` or
`PULL_REQUEST_TEMPLATE.md`, else default `## Summary` + `## Test Plan`), capture
`HEAD_SHA` and `BOT_REVIEW_BASELINE` immediately and persist both.

→ Read `<PLUGIN_ROOT>/lib/ship/push-and-pr.md` for the push command, PR
creation logic, template detection, and the post-push capture block.

---

## Phase 3: CI Watch (Step 10)

```bash
set_loop_phase "$STATE_FILE" "ci-watch" "$WORKFLOW_STATE_PATH"
```

**MANDATORY — NO EXCEPTIONS:** You MUST verify that CI checks correspond to the
latest pushed `HEAD_SHA` before considering CI as passed. You MUST NOT:

- Assume passing checks from a prior commit apply to the current commit
- Rationalize that "only a minor fix was pushed so old checks are still valid"
- Skip the post-watch PR head verification
- Treat "no checks yet" as "checks passed"

The ENTIRE purpose of CI is to validate the EXACT code being merged. Stale check
results are meaningless.

If no `.github/workflows/*.yml` files exist → persist `has_ci: false` with
`ci_skip_reason: no-workflow-files` and skip to Step 11. When workflow files
exist but no checks register, only skip CI after Step 10b establishes that no
active workflow applies to the current PR.

→ Read `<PLUGIN_ROOT>/lib/ship/ci-watch.md` for: HEAD-SHA
capture-and-verify, the 120s wait for checks to register against the SHA,
combined check-run and commit-status aggregation, post-watch SHA shift
detection (concurrent push →
fetch+reset to new HEAD, reset pass counter, set phase to `reviewing`, restart
from Step 5), and CI failure recovery.

---

## Phase 4: Bot Watch (Step 11)

```bash
set_loop_phase "$STATE_FILE" "bot-watching" "$WORKFLOW_STATE_PATH"
```

Discover review bots from REST formal reviews, REST top-level issue comments,
and GraphQL review-thread comments; use an exact-head check snapshot for
status-only bots such as Greptile. Match against
`<PLUGIN_ROOT>/skills/address-review/bot-registry.md`. Persist
`discovered_bots` (comma-separated). If none are found and
`BOT_REVIEW_BASELINE` is recent (<2 min), follow the bounded automatic wait in
`bot-watch.md`.

For polling, Read `<PLUGIN_ROOT>/skills/address-review/watch-loop.md`
Steps 12a–12d:

- All bots approved → Step 13
- New comments / `CHANGES_REQUESTED` → Step 12
- Timeout (5 min) → apply the deterministic re-trigger or incomplete outcome
  in `watch-loop.md`

→ Read `<PLUGIN_ROOT>/lib/ship/bot-watch.md` for the full GraphQL query
and the bot-not-detected-yet retry policy.

---

## Phase 5: Address Bot Feedback (Step 12)

```bash
set_loop_phase "$STATE_FILE" "addressing" "$WORKFLOW_STATE_PATH"
```

Fetch and rebase against base (`git -C "$WORKTREE_PATH" fetch origin "$BASE_BRANCH" && git -C "$WORKTREE_PATH" rebase
"origin/$BASE_BRANCH"`). If conflicts cannot be resolved, abort the rebase,
set `WORKFLOW_REASON=rebase-conflict`, follow **Hard Invariant Failure**, and
stop before applying or pushing fixes.

Execute address-review through the caller/component contract in
`address-bots.md`, follow Steps 2–11 only, and require its structured
`result=complete` before continuing. Skip Step 1 and Step 12 because ship owns
checkout and bot watch.

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` BEFORE pushing (catches fast bot
responses). Then push, capture `HEAD_SHA` after push. Persist both. Return to
Step 10 — re-watch CI for the new SHA.

→ Read `<PLUGIN_ROOT>/lib/ship/address-bots.md` for the rebase-or-abort
handling and the baseline-then-push ordering.

---

## Phase 6: Merge (Step 13)

```bash
set_loop_phase "$STATE_FILE" "merging" "$WORKFLOW_STATE_PATH"
```

**CRITICAL: NEVER use `--admin`. NEVER bypass branch protection.** If merge
fails due to protection, STOP and inform the user — do NOT retry with elevated
privileges.

→ Read `<PLUGIN_ROOT>/lib/ship/merge.md` for: final-checks (CI green, no
unresolved threads, no human `CHANGES_REQUESTED`), `--no-merge` early exit,
merge-strategy selection (`SHIP_MERGE_STRATEGY`, then `--squash` > `--rebase` > `--merge`), the full
REST `mergeable_state` decision tree (`unknown`/`dirty`/`blocked`/`clean`/
`has_hooks`/`behind`/`unstable`/other), merge-queue handling, and the
summary-line rendering (uses `coverage_skip_reason` to avoid `N/A%`). Output
the Step 13g result after the merge succeeds. Embedded ship returns structured
state without a marker; standalone ship outputs `<done>SHIPPED</done>`.

---

## Phase Flow Summary

```
5–8 local-review → 9 pushing → 10 ci-watch → 11 bot-watch ⇄ 12 addressing
                                                ↓
                                            13 merging → structured result
```

`[coverage-check]` runs on every final pass that changes source files.
`--skip-coverage` can avoid work only for source-free changes.
`[e2e-testing]` is mandatory for UI-visible diffs. Missing MCP/browser tooling
or an unavailable dev server records `e2e_result=blocked` and stops before push
or merge. Non-UI diffs may record `e2e_result=skipped`.

## Verification Gate (HARD — applies before ANY completion signal)

Before returning a shipped result, every claim MUST have FRESH evidence
from THIS session — actual command output, not narrative:

- **"Tests pass"** → `go -C "$WORKTREE_PATH" test` output with "ok" lines, zero failures
- **"Build succeeds"** → `go -C "$WORKTREE_PATH" build ./...` exit 0
- **"Generation is current"** → configured generation target exits 0 with generated changes included
- **"Lint passes"** → configured lint command exits 0
- **"CI passes"** → an exact-head `github_check_snapshot` with all registered
  items terminal and successful
- **"Bot approvals"** → `github_pr_reviews` plus the review-thread evidence
  used by the bot watch
- **"PR merged"** → validated REST merge output or required merge-queue
  enqueue output

**Red-flag language check** — if you are about to write "should work" / "should
be fine" / "probably" / "likely" / "I believe" / "I think" / "Done!" /
"Shipped!" without preceding command output proving it, STOP and run
verification instead.

## Completion Criteria

Return `result=shipped` ONLY when ALL of these are true. Embedded ship persists
that result at its child path without a marker. Standalone ship additionally
outputs `<done>SHIPPED</done>`:

1. Local LLM review passes completed (clean or max passes reached), or a
   session-local review is durably recorded as `void`/`skipped` with reason
   `session-boundary`/`headless-worker` and the exact current head passes CI.
   An unrecorded timeout, error, or early exit never satisfies this criterion.
2. Coverage verified for changed source files (or not applicable because the
   diff is source-free / all changed Go files are `package main`)
3. E2E smoke tests passed for UI-visible diffs (or skipped only because the
   diff is non-UI / no web components)
4. Changes pushed to remote
5. PR exists
6. CI passes (or no CI configured) — with output shown above
7. Bot approvals received (or no bots configured) — with output shown above
8. PR merged (or `--no-merge` specified) — with output shown above

**Safety note:** If you've iterated 15+ times without completion, document the
blocking evidence and stop incomplete. Do not bypass a completion criterion.

## Cancel

`/cancel-loop ship` cleanly exits the loop.

## Further Reading

All sibling files live under `<PLUGIN_ROOT>/lib/ship/`:

- `state-fields.md` — full jq invocation for Step 1's persist; field name reference
- `prerequisites.md` — Step 4 LLM diagnostic output
- `local-review.md` — Phase 1 (Steps 5–8): review/fix/verify/coverage/e2e/commit
- `push-and-pr.md` — Phase 2 (Step 9): push, PR creation, template detection, baseline capture
- `ci-watch.md` — Phase 3 (Step 10): SHA-anchored CI watch, post-watch shift detection, failure recovery
- `bot-watch.md` — Phase 4 (Step 11): split REST/GraphQL bot discovery, retry-on-empty policy
- `address-bots.md` — Phase 5 (Step 12): rebase, address-review delegation, baseline-then-push ordering
- `merge.md` — Phase 6 (Step 13): final checks, merge strategy detection, REST mergeability tree, summary rendering
