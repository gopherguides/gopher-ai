---
argument-hint: "[--llm codex|gemini|ollama|fable] [--passes <n>] [--no-merge] [--skip-coverage] [--coverage-threshold <n>] [--tier flex|standard|priority]"
description: "Ship a PR through verify, CI watch, and merge"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent", "mcp__chrome-devtools-mcp__navigate_page", "mcp__chrome-devtools-mcp__take_screenshot", "mcp__chrome-devtools-mcp__list_console_messages", "mcp__chrome-devtools-mcp__list_network_requests", "mcp__chrome-devtools-mcp__fill", "mcp__chrome-devtools-mcp__click", "mcp__chrome-devtools-mcp__new_page"]
---

# Ship PR

## GraphQL Budget Discipline (read first)

GitHub meters **two separate** hourly budgets: ~5,000 **GraphQL points/hr** and
~5,000 **REST requests/hr**. Tools that drive a GitHub Project board (e.g.
Detent) already spend the GraphQL budget on ProjectV2 polling (Projects v2 is
GraphQL-only). If this skill *also* leans on GraphQL for routine PR ops, the two
collide and exhaust the shared pool — a CI-watch loop alone can burn hundreds of
GraphQL points per PR. **Keep this skill's work on the REST budget:**

- **CI status / watch:** `gh api repos/<o>/<r>/commits/<sha>/check-runs` or
  `gh run watch <run-id> --exit-status`. Avoid looping `gh pr checks --watch` /
  `gh pr view` to poll CI (GraphQL-routed).
- **PR / mergeability / state reads:** `gh api repos/<o>/<r>/pulls/<N>` (REST,
  has `mergeable`/`mergeable_state`) instead of `gh pr view --json` or
  `gh api graphql` mergeState queries.
- **Merge:** `gh api --method PUT repos/<o>/<r>/pulls/<N>/merge -f merge_method=<m> -f sha=<sha>`
  instead of `gh pr merge` (GraphQL).
- **Reserve GraphQL** only for things with no REST equivalent (ProjectV2
  fields). If a GraphQL call hits `rate limit exceeded`, the REST budget is
  almost certainly fine — switch to REST, don't wait for the reset.

(The same discipline applies to the other go-workflow skills — `e2e-verify`,
`address-review`, `complete-issue`.)

## 0. State File Bootstrap

Before calling setup-loop, check if a state file already exists with a non-empty phase (re-entry). If so, **skip** setup-loop to preserve custom fields (`args`, `pass`, `pr_number`, `base_branch`, `no_merge`, `llm`, `discovered_bots`).

```bash
STATE_FILE=".local/state/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi
```

**Only call setup-loop on fresh starts** (no state file or empty phase):

!`if [ -f ".local/state/ship.loop.local.json" ] && [ -n "$(jq -r '.phase // empty' .local/state/ship.loop.local.json 2>/dev/null)" ]; then echo "Re-entry detected — skipping setup-loop."; elif [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" '{"reviewing":"Resume LLM review pass.","fixing":"Continue fixing LLM review findings.","verifying":"Re-run verification: build, test, lint.","coverage-check":"Resume coverage analysis for changed files.","e2e-testing":"Resume e2e testing. Restart dev server if needed.","pushing":"Resume push and PR creation.","ci-watch":"Resume CI monitoring. Run gh pr checks and fix any failures.","bot-watching":"Resume bot approval polling (Step 11). Check discovered bots for approval status. If bots request changes, go to Step 12. If all approved, go to Step 13.","addressing":"Resume addressing bot review feedback (Steps 2-11 of address-review). After fixes, return to CI watch.","merging":"Verify CI green and bot approval, then merge the PR."}'; fi`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: `codex` (default), `gemini`, `ollama`, `fable` (Claude subagent — no external CLI; prefer when the diff was written by Codex so a different model family reviews it)
- `--passes <n>`: max LLM review passes (default: 3)
- `--no-merge`: stop after bot approval, don't auto-merge
- `--skip-coverage`: skip coverage analysis. E2E may be reused only when a
  prior `/go-workflow:e2e-verify` pass is recorded; it is not skipped
  automatically for UI-visible diffs.
- `--coverage-threshold <n>`: override the default 60% threshold
- `--tier <value>`: gemini service tier (`flex`/`standard`/`priority`; gemini only; default: unset)

Store as `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`, `SKIP_COVERAGE`, `COVERAGE_THRESHOLD` (default `60`), `GEMINI_TIER`.

**Persist arguments** to `.local/state/ship.loop.local.json` via `jq` so the stop-hook can recover all fields on re-entry. The full jq invocation lives in `${CLAUDE_PLUGIN_ROOT}/lib/ship/state-fields.md` — fields written: `args, llm, pass, no_merge, pr_number, base_branch, bot_review_baseline, discovered_bots, has_ci, skip_coverage, coverage_threshold, coverage_result, coverage_tests_generated, e2e_required, e2e_attempted, e2e_result, e2e_skip_reason, e2e_pages_tested, review_clean, head_sha, gemini_tier`.

## 2. Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".local/state/ship.loop.local.json"
[ -f "$STATE_FILE" ] && read_loop_state "$STATE_FILE"
```

If `PHASE` is set (non-empty), this is a stop-hook re-entry. Restore all fields listed in Step 1 from state file via `jq -r '.<field> // empty'`. If `review_clean == "true"`, set `REVIEW_CLEAN=true` to preserve the clean-review fast path.

Then jump to the matching phase:

| Phase | Step |
|-------|------|
| `reviewing` | Step 5 (Phase 1) |
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

## 3. Detect Context

```bash
CURRENT_BRANCH=$(git branch --show-current)
PR_JSON=$(gh pr view --json number,baseRefName --jq '.' 2>/dev/null || echo "")

if [ -n "$PR_JSON" ]; then
  PR_NUM=$(echo "$PR_JSON" | jq -r '.number')
  BASE_BRANCH=$(echo "$PR_JSON" | jq -r '.baseRefName')
  echo "PR #$PR_NUM targets: $BASE_BRANCH"
else
  BASE_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main")
  PR_NUM=""
  echo "No PR found. Base: $BASE_BRANCH"
fi
```

**CRITICAL:** If `CURRENT_BRANCH == BASE_BRANCH` → **STOP**, do not ship from the default branch. Inform the user and ask how to proceed.

If `git status --porcelain` shows uncommitted changes, ask the user: "Commit them before shipping, or abort?"

Persist `BASE_BRANCH` and `PR_NUM` (if found) in the state file.

## 4. Prerequisite Check

Verify the selected LLM CLI is installed. **CRITICAL: Never silently fall back** — always use `AskUserQuestion`. The detection bash, diagnostic block, and four-option `AskUserQuestion` (**Retry** / **Debug / Install instructions** / **Use agent-based review** / **Abort**) live in `${CLAUDE_PLUGIN_ROOT}/lib/ship/prerequisites.md`.

**On re-entry (Step 2):** Restore `USE_AGENT_REVIEW` from state. If `"true"`, set `CODEX_EXEC_FALLBACK=true` — do NOT re-ask. If `llm_check_failed=="true"` AND `use_agent_review!="true"`, re-present the `AskUserQuestion`.

---

## Phase 1: Local LLM Review (Steps 5–8)

LLM review → fix → verify → coverage gate (final pass) → E2E smoke (when applicable) → commit → loop decision.

**Coverage gate (Step 7.5, final pass only):** Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md` and follow Steps A–F with `BASE_BRANCH=origin/${BASE_BRANCH}`, `STATE_FILE`, `SKIP_COVERAGE`, `COVERAGE_THRESHOLD` from parsed args.

**Loop decision (Step 8):** clean review (`REVIEW_CLEAN=true`) OR `PASS >= MAX_PASSES` → Phase 2. Otherwise → back to Step 5. Always stage only fixed files (never `git add -A`).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/local-review.md` for: LLM execution paths (codex exhaustive/quick, fable Claude-subagent, gemini, ollama, agent-based fallback), structured-JSON vs free-text parsing, `confidence_score < 0.3` filter, codegen-drift check (`make generate|gen|codegen|sqlc|proto|templ`), E2E skip conditions, and the staged-commit + pass-counter increment.

---

## Phase 2: Push and PR Creation (Step 9)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "pushing"
```

Push to remote (use the configured tracking remote and PR `headRefName`), ensure a PR exists (auto-detect template at `.github/pull_request_template.md` or `PULL_REQUEST_TEMPLATE.md`, else default `## Summary` + `## Test Plan`), capture `HEAD_SHA` and `BOT_REVIEW_BASELINE` immediately and persist both.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/push-and-pr.md` for the push command, PR creation logic, template detection, and the post-push capture block.

---

## Phase 3: CI Watch (Step 10)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "ci-watch"
```

**MANDATORY — NO EXCEPTIONS:** You MUST verify that CI checks correspond to the latest pushed `HEAD_SHA` before considering CI as passed. You MUST NOT:

- Assume passing checks from a prior commit apply to the current commit
- Rationalize that "only a minor fix was pushed so old checks are still valid"
- Skip SHA verification because `gh pr checks --watch` returned success
- Treat "no checks yet" as "checks passed"

The ENTIRE purpose of CI is to validate the EXACT code being merged. Stale check results are meaningless.

If no `.github/workflows/*.yml` files exist → persist `has_ci: false` and skip to Step 11.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/ci-watch.md` for: HEAD-SHA capture-and-verify, the 120s wait for checks to register against the SHA, `gh pr checks --watch`, post-watch SHA shift detection (concurrent push → fetch+reset to new HEAD, reset pass counter, set phase to `reviewing`, restart from Step 5), and CI failure recovery.

---

## Phase 4: Bot Watch (Step 11)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "bot-watching"
```

Discover review bots via the GraphQL query for `reviews + reviewThreads + comments` author logins; also check `gh pr checks` names for status-only bots (e.g., Greptile). Match against `${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md`. Persist `discovered_bots` (comma-separated). If none found and `BOT_REVIEW_BASELINE` is recent (<2 min), `AskUserQuestion` whether to wait or proceed.

For polling, Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md` Steps 12a–12d:

- All bots approved → Step 13
- New comments / `CHANGES_REQUESTED` → Step 12
- Timeout (5 min) → `AskUserQuestion`

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/bot-watch.md` for the full GraphQL query and the bot-not-detected-yet retry policy.

---

## Phase 5: Address Bot Feedback (Step 12)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "addressing"
```

Fetch and rebase against base (`git fetch origin "$BASE_BRANCH" && git rebase "origin/$BASE_BRANCH" || git rebase --abort`); if rebase aborts on conflicts, proceed without rebasing — user resolves manually.

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow **Steps 2–11 only** (skip Step 1 / loop init — we're already managed; skip Step 12 / bot-watch — we own that in Step 11).

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` BEFORE pushing (catches fast bot responses). Then push, capture `HEAD_SHA` after push. Persist both. Return to Step 10 — re-watch CI for the new SHA.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/address-bots.md` for the rebase-or-abort handling and the baseline-then-push ordering.

---

## Phase 6: Merge (Step 13)

```bash
set_loop_phase ".local/state/ship.loop.local.json" "merging"
```

**CRITICAL: NEVER use `--admin`. NEVER bypass branch protection.** If merge fails due to protection, STOP and inform the user — do NOT retry with elevated privileges.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/ship/merge.md` for: final-checks (CI green, no unresolved threads, no human `CHANGES_REQUESTED`), `--no-merge` early exit, merge-strategy auto-detection (`--merge` > `--squash` > `--rebase`), the full `mergeStateStatus` decision tree (`UNKNOWN`/`CONFLICTING`/`BLOCKED`/`CLEAN`/`HAS_HOOKS`/`BEHIND`/`UNSTABLE`/other), merge-queue handling, and the summary-line rendering (uses `coverage_skip_reason` to avoid `N/A%`). Output `<done>SHIPPED</done>` after the merge succeeds.

---

## Phase Flow Summary

```
5–8 local-review → 9 pushing → 10 ci-watch → 11 bot-watch ⇄ 12 addressing
                                                ↓
                                            13 merging → <done>SHIPPED</done>
```

`[coverage-check]` runs only on the final pass when `--skip-coverage` isn't set.
`[e2e-testing]` is mandatory for UI-visible diffs. Missing MCP/browser tooling
or an unavailable dev server records `e2e_result=blocked` and stops before push
or merge. Non-UI diffs may record `e2e_result=skipped`.

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>SHIPPED</done>`, every claim MUST have FRESH evidence from THIS session — actual command output, not narrative:

- **"Tests pass"** → `go test` output with "ok" lines, zero failures
- **"Build succeeds"** → `go build ./...` exit 0
- **"CI passes"** → `gh pr checks` with all checks green
- **"Bot approvals"** → `gh pr view --json reviews --jq '.reviews[] | {author: .author.login, state: .state}'` with APPROVED
- **"PR merged"** → merge output or `gh pr view` showing MERGED

**Red-flag language check** — if you are about to write "should work" / "should be fine" / "probably" / "likely" / "I believe" / "I think" / "Done!" / "Shipped!" without preceding command output proving it, STOP and run verification instead.

## Completion Criteria

Output `<done>SHIPPED</done>` ONLY when ALL of these are true:

1. LLM review passes completed (clean or max passes reached)
2. Coverage verified for changed files (or skipped via `--skip-coverage`)
3. E2E smoke tests passed for UI-visible diffs (or skipped only because the
   diff is non-UI / no web components)
4. Changes pushed to remote
5. PR exists
6. CI passes (or no CI configured) — with output shown above
7. Bot approvals received (or no bots configured) — with output shown above
8. PR merged (or `--no-merge` specified) — with output shown above

**Safety note:** If you've iterated 15+ times without completion, document what's blocking and ask the user.

## Cancel

`/cancel-loop ship` cleanly exits the loop.

## Further Reading

All sibling files live under `${CLAUDE_PLUGIN_ROOT}/lib/ship/`:

- `state-fields.md` — full jq invocation for Step 1's persist; field name reference
- `prerequisites.md` — Step 4 LLM diagnostic output
- `local-review.md` — Phase 1 (Steps 5–8): review/fix/verify/coverage/e2e/commit
- `push-and-pr.md` — Phase 2 (Step 9): push, PR creation, template detection, baseline capture
- `ci-watch.md` — Phase 3 (Step 10): SHA-anchored CI watch, post-watch shift detection, failure recovery
- `bot-watch.md` — Phase 4 (Step 11): GraphQL bot discovery, retry-on-empty policy
- `address-bots.md` — Phase 5 (Step 12): rebase, address-review delegation, baseline-then-push ordering
- `merge.md` — Phase 6 (Step 13): final checks, merge strategy detection, mergeStateStatus tree, summary rendering
