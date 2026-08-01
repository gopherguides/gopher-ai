---
name: ship
description: "Ship a PR end-to-end: verify locally, push, create/update the PR, watch CI, handle review feedback, and merge without admin override. Use for 'ship', 'ship it', or 'push and merge'. SKIP if the user only wants a PR opened; use `create-pr`."
argument-hint: "[--llm codex|gemini|ollama|fable] [--passes <n>] [--no-merge] [--skip-coverage] [--coverage-threshold <n>] [--tier flex|standard|priority]"
disable-model-invocation: true
---

# Ship PR

Before requesting decisions or delegating work, read
`${CLAUDE_PLUGIN_ROOT}/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `${CLAUDE_PLUGIN_ROOT}/lib/decision-gates.md` before resolving any workflow
choice.

Load the shared GitHub REST helpers before any GitHub workflow operation:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/github-rest.sh"
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

Before calling setup-loop, check if a state file already exists with a non-empty
phase (re-entry). If so, **skip** setup-loop to preserve custom fields (`args`,
`pass`, `pr_number`, `base_branch`, `no_merge`, `llm`, `discovered_bots`).

```bash
STATE_FILE=".local/state/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi
```

Only call setup-loop on fresh starts (no state file or empty phase):

```bash
if [ -f ".local/state/ship.loop.local.json" ] && [ -n "$(jq -r '.phase // empty' .local/state/ship.loop.local.json 2>/dev/null)" ]; then
  echo "Re-entry detected — skipping setup-loop."
elif [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then
  echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."
  exit 1
else
  "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" "$(jq -c . "${CLAUDE_PLUGIN_ROOT}/lib/ship/resume-messages.json")"
fi
```

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

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
`LLM_EXPLICIT=true` only when `$ARGUMENTS` contains `--llm`; otherwise it is
`false`.

Persist arguments to `.local/state/ship.loop.local.json` via `jq` so the
stop-hook can recover all fields on re-entry. The full jq invocation lives in
`${CLAUDE_PLUGIN_ROOT}/lib/ship/state-fields.md` — fields written: `args`,
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
TMP=".local/state/ship.loop.local.json.tmp"
jq --arg reason "$WORKFLOW_REASON" \
  '.workflow_result = "incomplete" | .workflow_reason = $reason | .phase = "incomplete" | .completion_promise = "INCOMPLETE"' \
  ".local/state/ship.loop.local.json" > "$TMP" && mv "$TMP" ".local/state/ship.loop.local.json"
```

Report `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=$WORKFLOW_REASON`,
output `<done>INCOMPLETE</done>`, and stop. Never ask for permission to bypass
the invariant and never output `<done>SHIPPED</done>` on this path.

## 2. Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".local/state/ship.loop.local.json"
[ -f "$STATE_FILE" ] && read_loop_state "$STATE_FILE"
```

If `PHASE` is set (non-empty), this is a stop-hook re-entry. Restore all fields
listed in Step 1 from state file via `jq -r '.<field> // empty'`. If
`review_clean == "true"`, set `REVIEW_CLEAN=true` to preserve the clean-review
fast path.

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
CURRENT_BRANCH=$(git branch --show-current)
LOCAL_HEAD_SHA=$(git rev-parse HEAD)

if PR_JSON=$(github_current_pr "$CURRENT_BRANCH" "$LOCAL_HEAD_SHA"); then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.base.ref')
  echo "PR #$PR_NUM targets: $BASE_BRANCH"
else
  PR_LOOKUP_STATUS=$?
  if [ "$PR_LOOKUP_STATUS" -ne 4 ]; then
    WORKFLOW_REASON="current-pr-api-error"
  fi
  BASE_BRANCH=$(gh api "repos/{owner}/{repo}" --jq '.default_branch')
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

If `git status --porcelain` shows uncommitted changes, resolve a
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

Persist `BASE_BRANCH` and `PR_NUM` (if found) in the state file.

## 4. Prerequisite Check

Verify the selected LLM CLI is installed. Read
`${CLAUDE_PLUGIN_ROOT}/lib/ship/prerequisites.md` for the evidence-based
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
`${CLAUDE_PLUGIN_ROOT}/lib/coverage/coverage-verification.md` and follow
Steps A–F with `BASE_BRANCH=origin/${BASE_BRANCH}`, `STATE_FILE`,
`SKIP_COVERAGE`, `COVERAGE_THRESHOLD` from parsed args.

**Loop decision (Step 8):** clean review (`REVIEW_CLEAN=true`) OR
`PASS >= MAX_PASSES` → Phase 2. Otherwise → back to Step 5. Always stage only
fixed files (never `git add -A`).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/local-review.md` for: LLM execution
paths (codex exhaustive/quick, fable Claude-subagent, gemini, ollama,
agent-based fallback), structured-JSON vs free-text parsing,
`confidence_score < 0.3` filter, codegen-drift check
(`make generate|gen|codegen|sqlc|proto|templ`), E2E skip conditions, and the
staged-commit + pass-counter increment.

---

## Phase 2: Push and PR Creation (Step 9)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "pushing"
```

Push to remote (use the configured tracking remote and PR `headRefName`), ensure
a PR exists (auto-detect template at `.github/pull_request_template.md` or
`PULL_REQUEST_TEMPLATE.md`, else default `## Summary` + `## Test Plan`), capture
`HEAD_SHA` and `BOT_REVIEW_BASELINE` immediately and persist both.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/push-and-pr.md` for the push command, PR
creation logic, template detection, and the post-push capture block.

---

## Phase 3: CI Watch (Step 10)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "ci-watch"
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

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/ci-watch.md` for: HEAD-SHA
capture-and-verify, the 120s wait for checks to register against the SHA,
combined check-run and commit-status aggregation, post-watch SHA shift
detection (concurrent push →
fetch+reset to new HEAD, reset pass counter, set phase to `reviewing`, restart
from Step 5), and CI failure recovery.

---

## Phase 4: Bot Watch (Step 11)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "bot-watching"
```

Discover review bots from REST formal reviews, REST top-level issue comments,
and GraphQL review-thread comments; use an exact-head check snapshot for
status-only bots such as Greptile. Match against
`${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md`. Persist
`discovered_bots` (comma-separated). If none are found and
`BOT_REVIEW_BASELINE` is recent (<2 min), follow the bounded automatic wait in
`bot-watch.md`.

For polling, Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md`
Steps 12a–12d:

- All bots approved → Step 13
- New comments / `CHANGES_REQUESTED` → Step 12
- Timeout (5 min) → apply the deterministic re-trigger or incomplete outcome
  in `watch-loop.md`

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/bot-watch.md` for the full GraphQL query
and the bot-not-detected-yet retry policy.

---

## Phase 5: Address Bot Feedback (Step 12)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "addressing"
```

Fetch and rebase against base (`git fetch origin "$BASE_BRANCH" && git rebase
"origin/$BASE_BRANCH"`). If conflicts cannot be resolved, abort the rebase,
set `WORKFLOW_REASON=rebase-conflict`, follow **Hard Invariant Failure**, and
stop before applying or pushing fixes.

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow
**Steps 2–11 only** (skip Step 1 / loop init — we're already managed; skip Step
12 / bot-watch — we own that in Step 11).

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` BEFORE pushing (catches fast bot
responses). Then push, capture `HEAD_SHA` after push. Persist both. Return to
Step 10 — re-watch CI for the new SHA.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/address-bots.md` for the rebase-or-abort
handling and the baseline-then-push ordering.

---

## Phase 6: Merge (Step 13)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "merging"
```

**CRITICAL: NEVER use `--admin`. NEVER bypass branch protection.** If merge
fails due to protection, STOP and inform the user — do NOT retry with elevated
privileges.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/merge.md` for: final-checks (CI green, no
unresolved threads, no human `CHANGES_REQUESTED`), `--no-merge` early exit,
merge-strategy selection (`SHIP_MERGE_STRATEGY`, then `--squash` > `--rebase` > `--merge`), the full
REST `mergeable_state` decision tree (`unknown`/`dirty`/`blocked`/`clean`/
`has_hooks`/`behind`/`unstable`/other), merge-queue handling, and the
summary-line rendering (uses `coverage_skip_reason` to avoid `N/A%`). Output
`<done>SHIPPED</done>` after the merge succeeds.

---

## Phase Flow Summary

```
5–8 local-review → 9 pushing → 10 ci-watch → 11 bot-watch ⇄ 12 addressing
                                                ↓
                                            13 merging → <done>SHIPPED</done>
```

`[coverage-check]` runs on every final pass that changes source files.
`--skip-coverage` can avoid work only for source-free changes.
`[e2e-testing]` is mandatory for UI-visible diffs. Missing MCP/browser tooling
or an unavailable dev server records `e2e_result=blocked` and stops before push
or merge. Non-UI diffs may record `e2e_result=skipped`.

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>SHIPPED</done>`, every claim MUST have FRESH evidence
from THIS session — actual command output, not narrative:

- **"Tests pass"** → `go test` output with "ok" lines, zero failures
- **"Build succeeds"** → `go build ./...` exit 0
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

Output `<done>SHIPPED</done>` ONLY when ALL of these are true:

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

All sibling files live under `${CLAUDE_PLUGIN_ROOT}/lib/ship/`:

- `state-fields.md` — full jq invocation for Step 1's persist; field name reference
- `prerequisites.md` — Step 4 LLM diagnostic output
- `local-review.md` — Phase 1 (Steps 5–8): review/fix/verify/coverage/e2e/commit
- `push-and-pr.md` — Phase 2 (Step 9): push, PR creation, template detection, baseline capture
- `ci-watch.md` — Phase 3 (Step 10): SHA-anchored CI watch, post-watch shift detection, failure recovery
- `bot-watch.md` — Phase 4 (Step 11): split REST/GraphQL bot discovery, retry-on-empty policy
- `address-bots.md` — Phase 5 (Step 12): rebase, address-review delegation, baseline-then-push ordering
- `merge.md` — Phase 6 (Step 13): final checks, merge strategy detection, REST mergeability tree, summary rendering
