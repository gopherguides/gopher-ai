---
argument-hint: "[--llm codex|gemini|ollama] [--passes <n>] [--no-merge]"
description: "Ship a PR: LLM review, push, CI watch, bot approval, merge"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion"]
---

# Ship PR

## 0. State File Bootstrap

Before calling setup-loop, check if a state file already exists with a non-empty phase (re-entry).
If so, **skip** setup-loop to preserve custom fields (`args`, `pass`, `pr_number`, `base_branch`, `no_merge`, `llm`, `discovered_bots`).

```bash
STATE_FILE=".claude/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  EXISTING_PHASE=$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null || true)
  if [ -n "$EXISTING_PHASE" ]; then
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  fi
fi
```

**Only call setup-loop on fresh starts** (no state file or empty phase):

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh then retry."; exit 1; elif [ ! -f ".claude/ship.loop.local.json" ] || [ -z "$(jq -r '.phase // empty' .claude/ship.loop.local.json 2>/dev/null)" ]; then "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" '{"reviewing":"Resume LLM review pass.","fixing":"Continue fixing LLM review findings.","verifying":"Re-run verification: build, test, lint.","pushing":"Resume push and PR creation.","ci-watch":"Resume CI monitoring. Run gh pr checks and fix any failures.","bot-watching":"Resume bot approval polling (Step 11). Check discovered bots for approval status. If bots request changes, go to Step 12. If all approved, go to Step 13.","addressing":"Resume addressing bot review feedback (Steps 2-11 of address-review). After fixes, return to CI watch.","merging":"Verify CI green and bot approval, then merge the PR."}'; fi`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: LLM to use for reviews. Options: `codex` (default), `gemini`, `ollama`
- `--passes <n>`: Maximum LLM review passes (default: 3)
- `--no-merge`: Stop after bot approval, don't auto-merge
- Remaining text: ignored

Store as `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`.

**Persist arguments to state file** for re-entry recovery. After parsing, merge these fields into `.claude/ship.loop.local.json` using `jq`:

```bash
STATE_FILE=".claude/ship.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg args "$ARGUMENTS" --arg llm "$LLM_CHOICE" --argjson pass 0 \
   --arg no_merge "$NO_MERGE" --arg pr_number "" --arg base_branch "" \
   --arg bot_review_baseline "" --arg discovered_bots "" --arg has_ci "" \
   '. + {args: $args, llm: $llm, pass: $pass, no_merge: $no_merge, pr_number: $pr_number, base_branch: $base_branch, bot_review_baseline: $bot_review_baseline, discovered_bots: $discovered_bots, has_ci: $has_ci}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

## 2. Re-entry Check

Read the loop state file:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".claude/ship.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry from the stop-hook. Recover state from persisted fields using `jq`:

1. Read `args` field and re-parse to restore `LLM_CHOICE`, `MAX_PASSES`, `NO_MERGE`
2. Read `pass`, `pr_number`, `base_branch`, `bot_review_baseline`, `llm`, `discovered_bots`, `has_ci` fields via `jq -r '.field // empty' "$STATE_FILE"`

Then skip to the corresponding phase:

- `reviewing` → go to Step 5
- `fixing` → go to Step 6
- `verifying` → go to Step 7
- `pushing` → go to Step 9
- `ci-watch` → go to Step 10
- `bot-watching` → go to Step 11
- `addressing` → go to Step 12
- `merging` → go to Step 13

If `PHASE` is empty or unset, this is a fresh start. Continue to Step 3.

## 3. Detect Context

### 3a. Auto-detect base branch and PR

```bash
CURRENT_BRANCH=$(git branch --show-current)
PR_JSON=$(gh pr view --json number,baseRefName --jq '.' 2>/dev/null || echo "")
```

**If a PR exists**, use the PR's base branch (handles PRs targeting non-default branches like release branches):

```bash
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

**CRITICAL:** If `CURRENT_BRANCH` equals `BASE_BRANCH` (e.g., both are `main`), **STOP** — do not ship from the default branch. Inform the user and ask how to proceed.

Store `BASE_BRANCH` and `PR_NUM` (if found) in state file.

### 3b. Check for uncommitted changes

```bash
git status --porcelain
```

If there are uncommitted changes, ask the user: "There are uncommitted changes. Commit them before shipping, or abort?"

## 4. Prerequisite Check

Verify the selected LLM CLI is installed. Fail fast with install instructions if not found.

```bash
if [ "$LLM_CHOICE" = "codex" ]; then
  command -v codex >/dev/null 2>&1 || { echo "codex not found. Install: npm install -g @openai/codex"; exit 1; }
elif [ "$LLM_CHOICE" = "gemini" ]; then
  command -v gemini >/dev/null 2>&1 || { echo "gemini not found. Install: npm install -g @google/gemini-cli"; exit 1; }
elif [ "$LLM_CHOICE" = "ollama" ]; then
  command -v ollama >/dev/null 2>&1 || { echo "ollama not found. Install: brew install ollama"; exit 1; }
fi
```

If the check fails, report the error, clean up the loop state file, and **stop without emitting the completion promise** (the PR was NOT shipped):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "ship"
```

Do NOT output `<done>SHIPPED</done>`. Simply inform the user of the missing prerequisite and stop.

---

## Phase 1: Local LLM Review (Steps 5-8)

### Step 5: Review Phase

Set phase to `reviewing`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".claude/ship.loop.local.json" "reviewing"
PASS=$(jq -r '.pass // 0' ".claude/ship.loop.local.json")
```

**Note:** The pass counter is incremented in Step 8 (after the review completes and findings are committed), not here. This prevents burning a pass number if the session exits during the review and re-enters.

#### 5a. Generate Diff

Fetch the base branch to ensure the ref exists locally (handles cases where the base branch has never been checked out):

```bash
git fetch origin "$BASE_BRANCH" 2>/dev/null || true
DIFF=$(git diff "origin/${BASE_BRANCH}...HEAD")
```

If the diff is empty, skip the review loop entirely — nothing to review. Proceed to Step 9 (pushing).

#### 5b. Run LLM Review

Execute review based on `LLM_CHOICE`:

**Codex:**

```bash
codex review --base "origin/$BASE_BRANCH"
```

**Gemini:**

```bash
gemini <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

**Ollama:**

```bash
ollama run codellama <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

Capture the output as `FINDINGS`.

#### 5c. Parse Findings

- If output equals `NO_ISSUES_FOUND` or has fewer than 20 characters: review is clean → skip to Step 9 (pushing)
- Otherwise: extract structured findings and display with pass number
- **Filter bot noise:** Silently discard findings containing usage-limit or quota messages
- **De-duplicate across passes:** If a finding from a previous pass appears again (same file, same line, same issue), skip it

### Step 6: Fix Phase

Set phase to `fixing`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "fixing"
```

For each finding from Step 5c:

1. Read the relevant file and surrounding code context
2. Evaluate the finding — is it valid and actionable?
3. If valid: make the fix using Edit tool
4. If not valid or intentionally skipped: record the reason
5. For testable fixes (changes observable behavior): generate a corresponding test
   - Check for existing test files (`_test.go`, `_test.ts`, `test_*.py`)
   - If table-driven tests exist, add a new case
   - If no test exists, create one following project conventions
   - Verify the new test passes

Track counts: `FIXED`, `SKIPPED` (with reasons).

### Step 7: Verify Phase

Set phase to `verifying`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "verifying"
```

Auto-detect project type and run appropriate verification:

**Go** (go.mod exists):

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true
```

**Node/TypeScript** (package.json exists):

```bash
npm run build
npm test
npm run lint 2>/dev/null || true
```

**Rust** (Cargo.toml exists):

```bash
cargo build
cargo test
cargo clippy 2>/dev/null || true
```

**Python** (pyproject.toml or setup.py exists):

```bash
pytest 2>/dev/null || python -m pytest
ruff check . 2>/dev/null || flake8 . 2>/dev/null || true
```

If any verification fails: analyze, fix, re-run until all pass.

### Step 8: Commit, Increment Pass, and Loop Decision

Stage only the files modified during the fix phase (do NOT use `git add -A`):

```bash
git add <list of files modified during fix phase>
```

**Increment the pass counter** now that the review-fix-verify cycle is complete:

```bash
CURRENT_PASS=$(jq -r '.pass // 0' ".claude/ship.loop.local.json")
NEW_PASS=$((CURRENT_PASS + 1))
TMP=".claude/ship.loop.local.json.tmp"
jq --argjson p "$NEW_PASS" '.pass = $p' ".claude/ship.loop.local.json" > "$TMP" && mv "$TMP" ".claude/ship.loop.local.json"
PASS=$NEW_PASS
```

Only commit if there are staged changes:

```bash
if ! git diff --cached --quiet; then
  git commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
fi
```

Check if we should continue reviewing:

- If `PASS >= MAX_PASSES` → proceed to Step 9
- Otherwise → go back to Step 5 for next review pass

---

## Phase 2: Push and PR Creation (Step 9)

### Step 9: Pushing

Set phase to `pushing`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "pushing"
```

#### 9a. Push to remote

Detect the correct remote and branch name from tracking config or PR metadata:

```bash
BRANCH_REMOTE=$(git config "branch.$(git branch --show-current).remote" 2>/dev/null || echo "origin")
PR_HEAD_BRANCH=$(gh pr view --json headRefName --jq '.headRefName' 2>/dev/null || git branch --show-current)
git push -u "$BRANCH_REMOTE" "HEAD:$PR_HEAD_BRANCH"
```

#### 9b. Ensure PR exists

If `PR_NUM` is empty (no existing PR), create one:

1. Check for a PR template at `.github/pull_request_template.md` (also check `.github/PULL_REQUEST_TEMPLATE.md`, `docs/`, repo root)
2. If found, read the template and use its section structure
3. If not found, use default format: `## Summary` + `## Test Plan`
4. Generate conventional commit title from commits: `<type>(<scope>): <subject>`
5. Check branch name and commit messages for issue references
6. Create PR targeting the detected base branch:

```bash
gh pr create --base "$BASE_BRANCH" --title "<title>" --body "$(cat <<'EOF'
<filled-in template or default body>
EOF
)"
```

Store the PR number:

```bash
PR_NUM=$(gh pr view --json number --jq '.number')
```

Persist `pr_number` in state file.

#### 9c. Capture bot review baseline

**CRITICAL: Capture immediately after push:**

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "Bot review baseline captured: $BOT_REVIEW_BASELINE"
```

Persist `bot_review_baseline` in state file.

---

## Phase 3: CI Watch (Step 10)

### Step 10: CI Watch

Set phase to `ci-watch`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "ci-watch"
```

First, check if CI workflow files exist:

```bash
HAS_WORKFLOWS=$(find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1)
```

If no workflow files exist → persist `has_ci: false` in state file and skip to Step 11.

**If workflows exist**, persist `has_ci: true` in state file and watch CI with extended retry to handle slow check registration:

```bash
for i in 1 2 3 4 5 6; do sleep 10 && gh pr checks "$PR_NUM" --watch && break; done
```

This waits up to 60 seconds for checks to appear (6 retries x 10s). If checks still haven't registered after all retries but workflow files exist, inform the user and ask whether to keep waiting or proceed.

If CI fails:
1. Analyze the failure: `gh pr checks "$PR_NUM" --json name,state,description`
2. Fix the issue
3. Commit the fix
4. Push: `git push`
5. Re-capture `BOT_REVIEW_BASELINE`: `BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)` and persist
6. Re-watch CI (go back to top of Step 10)

---

## Phase 4: Bot Watch (Step 11)

### Step 11: Bot Discovery and Watch

Set phase to `bot-watching` (distinct from address-review's `watching` phase to get ship-specific re-entry messages):

```bash
set_loop_phase ".claude/ship.loop.local.json" "bot-watching"
```

#### 11a. Discover review bots

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/bot-registry.md` for the bot registry table.

Query **all** author sources — formal reviews, review thread comments, AND top-level PR comments (issue comments) — since some bots (e.g., Claude) signal via ordinary PR comments:

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')

BOT_AUTHORS=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $pr: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $pr) {
        reviews(first: 100) {
          nodes {
            author { login }
            state
          }
        }
        reviewThreads(first: 100) {
          nodes {
            comments(first: 50) {
              nodes {
                author { login }
              }
            }
          }
        }
        comments(first: 100) {
          nodes {
            author { login }
          }
        }
      }
    }
  }
' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq -r '
  [
    .data.repository.pullRequest.reviews.nodes[].author.login,
    .data.repository.pullRequest.reviewThreads.nodes[].comments.nodes[].author.login,
    .data.repository.pullRequest.comments.nodes[].author.login
  ] | unique | .[]
')
```

Also check PR status checks for bots that signal via commit statuses rather than reviews (e.g., Greptile):

```bash
CHECK_BOTS=$(gh pr checks "$PR_NUM" --json name 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
```

Match both `BOT_AUTHORS` and `CHECK_BOTS` against the bot registry.

**If no review bots detected yet:** This may be because async bots haven't posted their first review. If `BOT_REVIEW_BASELINE` was captured less than 2 minutes ago, ask the user whether to wait or proceed:

Use `AskUserQuestion`: "No review bots detected yet. The push was recent — bots may still be starting. Wait for bots to respond, or proceed to merge without bot review?"

If the user chooses to wait, poll up to 3 times (30s apart). If still no bots after retries → proceed to Step 13 (merging).

**Persist discovered bots** to state file for re-entry recovery:

```bash
# Store as comma-separated list in state file
# e.g., discovered_bots: chatgpt-codex-connector[bot],coderabbitai[bot]
```

#### 11b. Poll for bot approval

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/watch-loop.md` for the complete polling logic.

Follow Steps 12a-12d from watch-loop.md:

- **All bots approved** → proceed to Step 13 (merging)
- **New comments / CHANGES_REQUESTED** → go to Step 12 (address feedback)
- **Timeout (5 min)** → ask user via `AskUserQuestion`

---

## Phase 5: Address Bot Feedback (Step 12)

### Step 12: Address Feedback

Set phase to `addressing` (distinct from `fixing` to ensure correct re-entry routing):

```bash
set_loop_phase ".claude/ship.loop.local.json" "addressing"
```

#### 12a. Fetch and rebase against base branch

Before applying fixes, ensure the branch is up to date with the base to avoid conflicts:

```bash
git fetch origin "$BASE_BRANCH"
git rebase "origin/$BASE_BRANCH" || git rebase --abort
```

If the rebase fails (conflicts), abort and inform the user. Proceed with fixes without rebasing — the user can resolve conflicts manually.

#### 12b. Apply address-review fixes

Read `${CLAUDE_PLUGIN_ROOT}/skills/address-review/SKILL.md` and follow Steps 2-11 only:

- **Skip Step 1** (loop init / PR checkout) — we're already on the branch, loop is managed by `/ship`
- **Skip Step 12** (bot watch) — we handle that in Step 11 above
- Do NOT create a second loop state file — all phases are managed under the `ship` loop

#### 12c. Capture baseline BEFORE push

**CRITICAL:** Capture `BOT_REVIEW_BASELINE` before pushing, not after. This ensures we don't miss fast bot responses that arrive between the push and the timestamp capture:

```bash
BOT_REVIEW_BASELINE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

Persist in state file. Then push the fixes.

Return to Step 10 (ci-watch) — set phase and re-watch CI before checking bot approval again.

---

## Phase 6: Merge (Step 13)

### Step 13: Merge

Set phase to `merging`:

```bash
set_loop_phase ".claude/ship.loop.local.json" "merging"
```

#### 13a. Final checks

1. Verify CI is green (skip if `has_ci` is `false` in state file — Step 10 already determined no CI exists): `gh pr checks "$PR_NUM"`
2. Check for unresolved review threads:
   ```bash
   OWNER=$(gh repo view --json owner --jq '.owner.login')
   REPO=$(gh repo view --json name --jq '.name')
   UNRESOLVED=$(gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           reviewThreads(first: 100) {
             nodes { isResolved }
           }
         }
       }
     }
   ' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length')
   ```
3. Check for **active** human `CHANGES_REQUESTED` (latest review per human reviewer, excluding bots):
   ```bash
   OWNER=$(gh repo view --json owner --jq '.owner.login')
   REPO=$(gh repo view --json name --jq '.name')
   BLOCKING_HUMANS=$(gh api graphql -f query='
     query($owner: String!, $repo: String!, $pr: Int!) {
       repository(owner: $owner, name: $repo) {
         pullRequest(number: $pr) {
           latestReviews(first: 50) {
             nodes {
               author { login }
               state
             }
           }
         }
       }
     }
   ' -f owner="$OWNER" -f repo="$REPO" -F pr="$PR_NUM" | jq '[.data.repository.pullRequest.latestReviews.nodes[] | select(.state == "CHANGES_REQUESTED") | select(.author.login | test("\\[bot\\]$") | not)] | length')
   ```

If there are unresolved threads or human `CHANGES_REQUESTED`, inform the user and ask how to proceed.

#### 13b. Check `--no-merge` flag

If `NO_MERGE` is `true`:
- Display summary (see below)
- Output `<done>SHIPPED</done>`
- Stop here

#### 13c. Auto-detect merge strategy and merge

```bash
OWNER=$(gh repo view --json owner --jq '.owner.login')
REPO=$(gh repo view --json name --jq '.name')
MERGE_SETTINGS=$(gh api "repos/$OWNER/$REPO" --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}' 2>/dev/null || echo '{}')
```

Determine the merge flag based on what the repo allows (prefer merge > squash > rebase):

```bash
MERGE_FLAG="--merge"
if echo "$MERGE_SETTINGS" | jq -e '.merge == true' >/dev/null 2>&1; then
  MERGE_FLAG="--merge"
elif echo "$MERGE_SETTINGS" | jq -e '.squash == true' >/dev/null 2>&1; then
  MERGE_FLAG="--squash"
elif echo "$MERGE_SETTINGS" | jq -e '.rebase == true' >/dev/null 2>&1; then
  MERGE_FLAG="--rebase"
fi
```

#### 13d. Merge the PR

```bash
gh pr merge "$PR_NUM" $MERGE_FLAG --delete-branch
```

#### 13e. Display summary

```
## Ship Complete

- **PR:** #<PR_NUM>
- **LLM:** <llm>
- **Review passes:** <n>
- **Findings addressed:** <n>
- **CI:** green
- **Bot approvals:** <list or "none required">
- **Merge strategy:** <merge|squash|rebase>
- **Merged:** yes (or "skipped — --no-merge")
```

Output `<done>SHIPPED</done>`

---

## Phase Flow Summary

```
Step 5-8: local-review (reviewing → fixing → verifying)
    ↓
Step 9: pushing
    ↓
Step 10: ci-watch
    ↓
Step 11: bot-watch (bot-watching)
    ↓                ↓
    ↓          Step 12: address-feedback (addressing)
    ↓                ↓
    ↓          → back to Step 10 (ci-watch)
    ↓
Step 13: merging
    ↓
<done>SHIPPED</done>
```

## Re-entry Matrix

| Phase at exit | Re-entry behavior |
|---|---|
| `reviewing` | Resume LLM review pass |
| `fixing` | Continue fixing LLM review findings |
| `verifying` | Re-run verification |
| `pushing` | Resume push and PR creation |
| `ci-watch` | Resume CI monitoring |
| `bot-watching` | Resume bot approval polling |
| `addressing` | Resume addressing bot review feedback (Steps 2-11 of address-review) |
| `merging` | Resume merge attempt |

## Completion Criteria

Output `<done>SHIPPED</done>` ONLY when ALL of these are true:

1. LLM review passes completed (clean or max passes reached)
2. Changes pushed to remote
3. PR exists
4. CI passes (or no CI configured)
5. Bot approvals received (or no bots configured)
6. PR merged (or `--no-merge` specified)

**Safety note:** If you've iterated 15+ times without completion, document what's blocking and ask the user for guidance.

## Cancel

Users can run `/cancel-loop ship` at any time to cleanly exit the loop.
