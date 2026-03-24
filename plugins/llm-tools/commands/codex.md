---
argument-hint: "<prompt>"
description: "Delegate a task to OpenAI Codex CLI"
allowed-tools: ["Bash", "Read", "AskUserQuestion"]
---

# Delegate to Codex

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command delegates tasks to OpenAI Codex CLI for autonomous execution.

**Usage:** `/codex <prompt>`

**Examples:**

| Command | Description |
|---------|-------------|
| `/codex refactor the auth module` | Refactor existing code |
| `/codex write tests for utils.ts` | Generate test files |
| `/codex fix the bug in checkout flow` | Debug and fix issues |
| `/codex explain how the API routes work` | Code explanation |
| `/codex add dark mode support` | Implement new features |
| `/codex review the auth changes` | Review with session context |

**Available Models:**

| Model | Best For |
|-------|----------|
| `gpt-5.4` | Latest frontier model, best overall (default) |
| `gpt-5.4-pro` | Maximum performance on complex tasks |
| `gpt-5.3-codex` | Previous generation frontier model |
| `gpt-5.1-codex-mini` | Simple tasks, cost-efficient |

Ask the user: "What would you like Codex to do?"

---

**If `$ARGUMENTS` is provided:**

Run a task using OpenAI Codex CLI with the prompt: $ARGUMENTS

## 1. Detect Review Mode

Check if the prompt contains "review" (case-insensitive). Then determine routing:

- If the prompt is **fix-oriented** (contains action words like "fix", "address", "resolve", "update" alongside "review" — e.g., "fix review comment", "address review feedback"), route to **Exec Flow**. These prompts need to modify files, which Review Flow cannot do.
- If the prompt is **review-oriented** (e.g., "review the auth changes", "review this PR"), route to **Review Flow**.
- Otherwise, continue with **Exec Flow**.

## 2. Review Fix Detection (applies to both flows)

Before running Codex in either flow, detect if the prompt is addressing review feedback (e.g., contains phrases like "fix review comment", "address feedback", "fix the issue from review", or the prompt originates from an `/address-review` context). If a review-fix prompt is detected:

**Capture baseline before running Codex:**

```bash
# Record current test file content hashes for comparison after Codex completes
# This detects both new files AND modifications to existing test files
# Uses find -exec for safe handling of paths with spaces
TEST_BASELINE=$(mktemp)
find . -name '*_test.go' -type f -exec sh -c '
  for f; do md5sum "$f" 2>/dev/null || md5 -r "$f" 2>/dev/null; done
' _ {} + | sort > "$TEST_BASELINE"
```

**For flows using stdin mode** (Exec Flow, Review Flow with PR/issue context): Append these instructions to the Codex prompt:

```text

---

## Test Generation Requirement

For every testable fix you make, write a corresponding test. A fix is testable if it changes observable behavior (return values, errors, side effects, HTTP responses). Skip tests for cosmetic changes (comments, formatting, renames, log changes).

- Check for existing `_test.go` files and table-driven tests for affected functions
- If a table-driven test exists, add a new case covering the fixed behavior
- If no test exists, create a new table-driven test
- Follow the existing test conventions in the package (testify vs stdlib, naming patterns)
- Verify all new tests pass
```

**For Review Flow without PR/issue context** (uses native `codex review --uncommitted/--base/--commit`): These commands don't support custom prompt injection. The fallback mechanism below is the primary way to ensure test coverage for this path.

### Review Fix Fallback (after either flow completes)

After Codex completes (either flow), check if any `_test.go` files were created or modified since the baseline by comparing content hashes:

```bash
# Compare current content hashes against pre-run baseline
# Uses find -exec for safe handling of paths with spaces
TEST_CURRENT=$(mktemp)
find . -name '*_test.go' -type f -exec sh -c '
  for f; do md5sum "$f" 2>/dev/null || md5 -r "$f" 2>/dev/null; done
' _ {} + | sort > "$TEST_CURRENT"

# Find lines only in current (new or modified files), excluding deletions
# comm -13 shows lines in file2 not in file1 (new/changed hashes)
CHANGED_TESTS=$(comm -13 "$TEST_BASELINE" "$TEST_CURRENT" | awk '{print $NF}' | sort -u)
rm -f "$TEST_BASELINE" "$TEST_CURRENT"

if [ -n "$CHANGED_TESTS" ]; then
  echo "Test files created or modified by Codex: $CHANGED_TESTS"
else
  echo "No test file changes from Codex"
fi
```

If no test files were created or modified by this Codex run AND the fix modified testable behavior, Claude generates the missing tests following the same guidelines above.

---

## Review Flow

Use this flow when the prompt contains "review".

### R1. Batched Questions (single AskUserQuestion call — NO commands run yet)

**Do NOT run any `gh` or `git` commands before asking the user questions.** PR detection is deferred until after the user requests context. This avoids wasting tokens on `gh pr view` calls when the user doesn't need PR context.

Ask all review configuration questions in a **single `AskUserQuestion` call** with up to 4 questions:

**Question 1 — "What do you want to review?"**

| Option | Description |
|--------|-------------|
| Changes vs branch (Recommended) | Review changes against a base branch |
| Uncommitted changes | Review staged, unstaged, and untracked changes |
| Specific commit | Review changes introduced by a commit |

**Question 2 — "Include PR/issue context?"**

| Option | Description |
|--------|-------------|
| Auto-detect (Recommended) | Auto-detect PR from current branch (skipped on main/master) |
| Provide PR number | Manually enter a PR number to use as context |
| Provide issue number | Manually enter an issue number to use as context |
| No context | Review code changes only |

**Question 3 — "Which model?"**

| Option | Description |
|--------|-------------|
| gpt-5.4 (Recommended) | Latest frontier model, best overall |
| gpt-5.4-pro | Maximum performance on complex tasks |
| gpt-5.3-codex | Previous generation frontier model |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

**Question 4 — "Review depth?"**

| Option | Description |
|--------|-------------|
| Exhaustive (Recommended) | `codex exec` with structured output — returns ALL findings in one pass |
| Single pass | One `codex review` pass (fastest, but limited to 2-3 findings) |
| Multi-pass (3) | Three `codex review` passes, de-duplicated |
| Multi-pass (custom) | Specify number of `codex review` passes |

Note: Exhaustive mode uses `codex exec --output-schema` to bypass the 2-3 finding limit of `codex review`. Multi-pass is available as a fallback but is less effective than exhaustive mode.

### R1.5. Conditional Follow-Up (only if needed)

After processing answers from R1, check if any selections require additional input. If so, ask all follow-ups in a **single `AskUserQuestion` call** (up to 4 questions):

- **"Changes vs branch"** was selected → ask: "What is the base branch?" (default: `main`)
- **"Specific commit"** was selected → ask: "Enter the commit SHA"
- **"Provide PR number"** was selected → ask: "Enter the PR number"
  - Validate input is numeric: `echo "$NUM" | grep -qE '^[0-9]+$'`
  - If invalid, show error and ask again
- **"Provide issue number"** was selected → ask: "Enter the issue number"
  - Validate input is numeric
- **"Multi-pass (custom)"** was selected → ask: "How many passes? (2-5)"
  - Validate numeric, clamp to range

If no follow-ups are needed (e.g., user chose "No context" + "Single pass"), proceed directly to R2.

Store all selections for use in R2.

### R2. Fetch PR/Issue Context (only if requested)

**Only run this step if the user selected "Auto-detect", "Provide PR number", or "Provide issue number" in R1.** If the user selected "No context", skip entirely to R3 — do NOT run any `gh` commands.

#### If "No context" was selected

Skip this entire section. Set `PR_DETECTED=false`. Proceed to R3.

#### If "Provide PR number" was selected

Fetch the specific PR:

```bash
PR_JSON=$(gh pr view "$NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews --jq '.' 2>/dev/null)
```

If successful, fetch linked issues and inline comments (see "Fetch PR details" below). Record `PR_DETECTED=true`.

#### If "Provide issue number" was selected

Fetch the specific issue:

```bash
gh issue view "$NUM" --json number,title,body,labels,comments --jq '.' 2>/dev/null
```

Skip PR-specific data (no reviews to fetch). Record `PR_DETECTED=true` (issue context available).

#### If "Auto-detect" was selected

**Early bail-out on default branch:** Before running any `gh` commands, check the current branch:

```bash
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$DEFAULT_BRANCH" ]; then
  DEFAULT_BRANCH="main"
fi
```

If `$CURRENT_BRANCH` equals `$DEFAULT_BRANCH`, `main`, or `master`: skip the automatic strategies (they would match unrelated merged PRs). Instead, ask the user via `AskUserQuestion`: "On default branch — auto-detect skipped. Enter a PR number for context, or press Enter to proceed without context." If the user provides a PR number, fetch it (same as "Provide PR number" path). Otherwise set `PR_DETECTED=false`.

**If NOT on the default branch, run detection strategies.** Each strategy is tried only if the previous one returned empty. All output is silenced with `2>/dev/null`.

**Strategy 1 — Current branch (works when branch name matches a PR):**

```bash
PR_JSON=$(gh pr view --json number,title,body,state,closingIssuesReferences,comments,reviews --jq '.' 2>/dev/null)
```

**Strategy 2 — Match HEAD commit against open PRs (handles worktrees):**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews 2>/dev/null)
  fi
fi
```

**Strategy 3 — Check merged/closed PRs (covers recently merged work):**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  PR_NUM=$(gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null)
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=$(gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews 2>/dev/null)
  fi
fi
```

**If no PR found after all strategies:** Ask the user via `AskUserQuestion`: "No PR found for current branch. Enter a PR number for context, or press Enter to proceed without context." If the user provides a PR number, fetch it (same as "Provide PR number" path). Otherwise set `PR_DETECTED=false`.

#### Fetch PR details (shared by Auto-detect and Provide PR number)

If `$PR_JSON` is not empty, fetch linked issues and inline review comments:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
PR_NUM=$(echo "$PR_JSON" | jq -r '.number' 2>/dev/null)

# Get linked issue numbers
ISSUE_NUMS=$(echo "$PR_JSON" | jq -r '.closingIssuesReferences[].number' 2>/dev/null)

# Fetch each linked issue
for NUM in $ISSUE_NUMS; do
  gh issue view "$NUM" --json number,title,body,labels,comments --jq '.' 2>/dev/null
done

# Fetch inline review comments
gh api "repos/$REPO/pulls/$PR_NUM/comments" --jq '.[] | {path, line, body, user: .user.login}' 2>/dev/null
```

**Filter out bot noise:** Silently discard any comment containing usage-limit or quota messages (e.g., "reached your Codex usage limits", "usage limits for code reviews", "see your limits"). These are automated bot messages with no relevance to the review. **Never treat external service quota/limit messages as blockers.**

Record `PR_DETECTED=true`. Display a brief summary:

```
Found PR for current branch:

**PR #<number>**: "<title>"
- State: <state>
- Comments: <count>
- Reviews: <count>
```

If linked issues were found:

```
**Linked Issues:**
- Issue #<num>: "<title>" (<labels>)
```

Store all PR/issue data for use in R3.

### R3. Run Codex Review

Assemble and execute the command based on review depth selection from R1.

**IMPORTANT:** Check exhaustive mode FIRST, regardless of context selection. Exhaustive mode works with or without PR/issue context.

#### If "Exhaustive" Mode Selected

Use `codex exec` with structured output to get ALL findings in one pass. This bypasses the 2-3 finding limit of `codex review`.

**Step 1: Generate the diff**

Based on review type from R1:

- **Uncommitted:** `git diff HEAD` (includes both staged and unstaged changes vs HEAD — do NOT also add `git diff --cached` as that duplicates staged hunks). For untracked files, use `git ls-files --others --exclude-standard` to get paths, then include their full content (e.g., `cat <file>`) in the diff section so new files are actually reviewed.
- **Changes vs branch:** `git diff <branch>...HEAD`
- **Specific commit:** `git show <sha>`

**Step 2: Assemble the review prompt**

Read the prompt template from `${CLAUDE_PLUGIN_ROOT}/prompts/codex-review.md` and fill placeholders:

- `{DIFF}` ← diff from Step 1
- `{SCOPE_HINT}` ← if provided, render as `## Specific Focus Area\n<value>`; otherwise empty
- `{REPO_GUIDELINES}` ← auto-detect `AGENTS.md` or `CLAUDE.md` in repo root; include if found
- `{PR_CONTEXT}` ← if PR/issue context was selected in R1, include PR title, body, linked issues, and review comments

**Step 3: Execute with structured output**

Write the assembled prompt to a temp file to avoid heredoc expansion issues with special characters in diffs:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt-XXXXXX)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"
REVIEW_JSON=$(codex exec -m <model> -s read-only \
  --output-schema "${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json" \
  - < "$PROMPT_FILE")
# Strip codex exec headers (version/config info printed before JSON)
REVIEW_JSON=$(printf '%s\n' "$REVIEW_JSON" | awk '/^\{/{found=1} found{print}')
# Guard: if stripping removed all output, codex exec returned no JSON
if [ -z "$REVIEW_JSON" ]; then
  echo "WARNING: codex exec produced no JSON output after header stripping"
  REVIEW_JSON='{"error":"no JSON output"}'
fi
rm -f "$PROMPT_FILE"
```

**Step 4: Parse structured JSON**

1. Validate JSON. If invalid, log warning and treat as free-text `FINDINGS`.
2. Filter findings with `confidence_score < 0.3` FIRST, then check for clean result (zero findings after filtering also triggers clean path).
3. Sort by priority (0 first), then confidence (highest first).
4. Store as `FINDINGS` for R4.

Skip to R4 (Report Results).

#### If Single/Multi-pass AND NO PR/Issue Context Selected

Use standard codex review commands:

**For uncommitted changes:**

```bash
codex review --uncommitted -c model=<model>
```

**For changes vs branch:**

```bash
codex review --base <branch> -c model=<model>
```

**For specific commit:**

```bash
codex review --commit <sha> -c model=<model>
```

Capture output as `FINDINGS`. Skip to R4 (or multi-pass loop below).

#### If Single/Multi-pass AND PR/Issue Context IS Included

Use `codex review -` (stdin mode) with the native review pipeline.

**Step 1: Generate the diff**

Based on review type from R1:

- **Uncommitted:** `git diff HEAD && git diff --cached && git ls-files --others --exclude-standard`
- **Changes vs branch:** `git diff <branch>...HEAD`
- **Specific commit:** `git show <sha>`

**Step 2: Build context block**

Include PR/issue context fetched in R2. Only include sections for which data exists.

**Size guard:** Before assembling, estimate the total context size (PR body + issue bodies + comments). If the combined text exceeds ~4000 characters, use the **Summary format** to avoid crowding the diff out of the model context. Otherwise use the **Full format**.

**Full format:**

```text
## PR/Issue Context

### PR #<number>: <title>
**State:** <state>
**Description:**
<PR body>

### Linked Issues

#### Issue #<number>: <title>
**Labels:** <labels>
**Description:**
<issue body>

**Issue Comments:**
- @<user>: <comment body>

### PR Comments
- @<user>: <comment body>

### PR Inline Review Comments
- **<file>:<line>** (@<user>): <comment body>

---

## Code Changes

\`\`\`diff
<diff output>
\`\`\`

---

## Review Instructions

Review the code changes above against the original requirements from the PR description and linked issues.

Specifically:
1. Verify the implementation addresses the stated requirements
2. Check that PR review comments have been addressed
3. Identify any requirements from the issue that may be missing
4. Flag any code that contradicts the original intent
5. Suggest improvements aligned with the stated goals
```

**Summary format** (used when context exceeds ~4000 chars):

```text
## PR/Issue Context (Summary)

**PR #<number>:** <title>
**Key Requirements:** <first 300 chars of PR body>

**Linked Issues:**
- #<num>: <title> - <first 150 chars of body>

**Review Feedback to Address:**
- <summarized key points from review comments>

---

## Code Changes

\`\`\`diff
<diff output>
\`\`\`

---

Review these changes against the requirements above. Ensure the implementation fulfills the original intent.
```

**Step 3: Execute review via stdin**

#### Single Pass (or no multi-pass selected)

```bash
codex review -c model=<model> - <<'EOF'
<constructed context block with diff>
EOF
```

Capture the output as `FINDINGS`.

#### Multi-Pass Review

**If multi-pass was selected in R1.5**, run the review loop:

**Pass 1:** Execute the same command as single pass above. Capture output as `PASS_1_FINDINGS`.

**Pass 2 through N:** Build an augmented prompt that appends a summarized "Previous Findings" section to the original context block. To avoid exceeding context limits, summarize prior findings rather than concatenating full text:

**Summarizing prior findings:**
- Extract a one-line summary for each finding: `<file>:<line> - <issue title>`
- Cap at 50 findings maximum; if more, include only the 50 most significant (by severity or detail level)
- Total summary should not exceed ~2000 characters

```text
<original context block with diff>

---

## Previous Findings Summary (from passes 1 through <current-1>)

The following issues have already been identified:
- <file1>:<line> - <issue title>
- <file2>:<line> - <issue title>
...

---

## Instructions for This Pass

You have already identified the issues listed above. For this pass, ONLY report NET-NEW findings that are NOT covered by the summary above. Focus on issues that were missed, edge cases, or deeper analysis.

If there are no new findings to report, respond with exactly: NO_NEW_FINDINGS
```

Execute:

```bash
codex review -c model=<model> - <<'EOF'
<augmented context block>
EOF
```

Capture output as `PASS_<N>_FINDINGS`.

**Early stop:** If the output, after stripping leading/trailing whitespace, equals exactly `NO_NEW_FINDINGS` or is substantively empty (fewer than 20 characters of content), stop the loop immediately. Do not match substring occurrences — only an exact trimmed match triggers early stop.

**After all passes complete:** Proceed to de-duplication.

#### De-Duplicate Findings

After collecting findings from all passes, de-duplicate before presenting results:

1. Parse each finding to extract: file path, exact line number/range, finding title/summary
2. Normalize titles for comparison: lowercase, collapse whitespace
3. Group by (file path, exact line number, normalized title) — use exact line matches only; do not merge nearby lines as this can collapse distinct issues in repeated patterns
4. For duplicate groups: keep the variant with the most detail or clearest explanation
5. Sort final findings by file path, then line number

Format the aggregated output as:

```text
## Code Review Findings (<N> passes, <M> unique findings)

### <file-path>

**Line <N>:** <finding title>
<finding detail>

### <next-file-path>

**Line <N>:** <finding title>
<finding detail>
```

If early stop occurred, note: "Review completed in X of Y passes (no additional findings in pass X)."

Store the final aggregated output as `FINDINGS` for use in R4.

### R4. Report Results

After execution completes:

- **Exhaustive mode:** Parse the structured JSON and display as a formatted table:

```
## Code Review Findings — <N> issues

| # | Priority | Category | File | Lines | Title | Confidence |
|---|----------|----------|------|-------|-------|------------|
| 1 | P0 | correctness | api/handler.go | 42-45 | Nil pointer on empty response | 0.95 |
```

Display `overall_explanation` and `overall_confidence_score` as a summary below the table. Show overall verdict (`patch is correct` / `patch is incorrect`).

- **Single pass:** Show the review output (`FINDINGS`) to the user
- **Multi-pass:** Show the aggregated, de-duplicated findings to the user with a summary header (e.g., "3 passes, 12 unique findings" or "Completed in 2 of 3 passes — no new findings in pass 2")

**If PR/issue context was included:**

Ask what to do next:

| Option | Description |
|--------|-------------|
| Follow-up | Run `codex resume --last` for additional questions |
| Address feedback | Switch to exec mode to implement suggested changes |
| Post to PR | Add review findings as a PR comment via `gh pr comment` |
| Done | Exit the review |

Default: `Done`

**If "Post to PR":**

Format the findings as a markdown comment and post. For multi-pass reviews, use the aggregated de-duplicated output:

```bash
gh pr comment <pr_number> --body "<formatted FINDINGS>"
```

**If no context was included:**

Ask if they want to run a follow-up review or switch to exec mode.

For follow-ups, use: `codex resume --last`

---

## Exec Flow

Use this flow for non-review tasks.

### 1. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.4 | Latest frontier model, best overall |
| gpt-5.4-pro | Maximum performance on complex tasks |
| gpt-5.3-codex | Previous generation frontier model |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.4`

### 2. Include Session Context (Optional)

Ask the user: "Do you want to include context from our current Claude session?"

| Option | Description |
|--------|-------------|
| No | Run Codex without session context |
| Summary | Include goal, decisions, and current task (~100 words) |
| Detailed | Include summary plus files changed/discussed (~200 words) |

Default: `No`

**If user selects "Summary":**

Generate a concise context block based on the current session:

```text
## Session Context

**Goal:** [What the user is trying to accomplish]
**Decisions:** [Key decisions made during this session]
**Current Task:** [What was being worked on when /codex was invoked]
```

**If user selects "Detailed":**

Generate an expanded context block based on the current session:

```text
## Session Context

**Goal:** [What the user is trying to accomplish]
**Decisions:** [Key decisions made during this session]
**Files Changed/Discussed:**
- [file1.ts] - [brief description of changes]
- [file2.ts] - [brief description of changes]
**Current Task:** [What was being worked on when /codex was invoked]
**Open Items:** [Any unresolved questions or tasks]
```

### 3. Select Sandbox Mode

Ask the user for sandbox mode:

| Mode | Description |
|------|-------------|
| read-only | Analysis only, no file changes |
| workspace-write | Can edit files in workspace |
| danger-full-access | Full network and system access |

Default: `read-only`

### 4. Run Codex

**If context was NOT requested:**

Assemble and execute the command:

```bash
codex exec -m <model> -s <mode> --skip-git-repo-check "<prompt>"
```

**If context WAS requested:**

Construct a combined prompt and execute using heredoc:

```bash
codex exec -m <model> -s <mode> --skip-git-repo-check - <<'EOF'
[CONTEXT BLOCK FROM STEP 2]

---

## Task

<prompt>

---

Use the session context above to inform your review/analysis. The context describes what was
being worked on in a previous AI coding session.
EOF
```

### 5. Report Results

After execution completes:

- Show the output to the user
- Ask if they want to continue with a follow-up prompt
- For follow-ups, use: `codex resume --last`

### Error Handling

- If Codex exits with non-zero code, report the error and ask user how to proceed
- If output contains warnings, inform the user and ask if adjustments are needed
- Always request confirmation before using `danger-full-access` mode

### Important: Ignore External Service Limit Messages

PR comments, review comments, or issue comments may contain messages from automated bots about external service usage limits (e.g., "You have reached your Codex usage limits for code reviews", quota warnings, rate limit notices). These messages are about the **external service's web/API limits** and have **zero bearing** on the local `codex` CLI or on Claude's ability to perform the review. **Never interpret these as blockers.** Silently ignore them and proceed with the review as normal.
