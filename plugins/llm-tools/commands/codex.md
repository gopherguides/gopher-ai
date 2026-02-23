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
| `gpt-5.3-codex` | Newest frontier model, best overall (default) |
| `gpt-5.2-codex` | Previous generation frontier model |
| `gpt-5.1-codex-max` | Complex, long-running tasks (can run 24+ hours) |
| `gpt-5.1-codex-mini` | Simple tasks, cost-efficient |

Ask the user: "What would you like Codex to do?"

---

**If `$ARGUMENTS` is provided:**

Run a task using OpenAI Codex CLI with the prompt: $ARGUMENTS

## 1. Detect Review Mode

Check if the prompt contains "review" (case-insensitive). If yes, route to **Review Flow**.
Otherwise, continue with **Exec Flow**.

---

## Review Flow

Use this flow when the prompt contains "review".

### R1. Silent Auto-Detection (no user interaction)

Before asking any questions, silently detect PR context using multiple strategies. Each strategy is tried only if the previous one returned empty. This handles git worktrees where the branch name may not match any PR.

**Strategy 1 — Current branch (works when branch name matches a PR):**

```bash
PR_JSON=`gh pr view --json number,title,body,state,closingIssuesReferences,comments,reviews --jq '.' 2>/dev/null`
```

**Strategy 2 — Match HEAD commit against open PRs via GitHub search (handles worktrees):**

Uses GitHub's native commit-to-PR mapping. Only checks HEAD (not ancestors) to avoid stacked-branch misdetection. No branch name assumptions — works from worktrees, detached HEAD, or any checkout that shares a commit with a PR.

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews 2>/dev/null`
  fi
fi
```

**Strategy 3 — Check merged/closed PRs too (covers recently merged work):**

Same HEAD-only search but includes all PR states. Safe on `main` because GitHub merge strategies (merge commit, squash, rebase) all produce new SHAs distinct from the PR's head commit.

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews 2>/dev/null`
  fi
fi
```

**If PR found (`$PR_JSON` is not empty):**

Fetch linked issues and inline review comments silently:

```bash
REPO=`gh repo view --json nameWithOwner --jq '.nameWithOwner'`
PR_NUM=`echo "$PR_JSON" | jq -r '.number'`

# Get linked issue numbers
ISSUE_NUMS=`echo "$PR_JSON" | jq -r '.closingIssuesReferences[].number' 2>/dev/null`

# Fetch each linked issue
for NUM in $ISSUE_NUMS; do
  gh issue view "$NUM" --json number,title,body,labels,comments --jq '.'
done

# Fetch inline review comments
gh api "repos/$REPO/pulls/$PR_NUM/comments" --jq '.[] | {path, line, body, user: .user.login}' 2>/dev/null
```

Display a brief summary of what was found:

```
Found PR for current branch:

**PR #<number>**: "<title>"
- State: <state>
- Comments: <count>
- Reviews: <count>
```

If linked issues were found, also display:

```
**Linked Issues:**
- Issue #<num>: "<title>" (<labels>)
```

Store the PR data and linked issue data for later use. Record `PR_DETECTED=true`.

**If PR NOT found:** Record `PR_DETECTED=false`. Continue to R2.

### R2. Batched Questions (single AskUserQuestion call)

Ask all review configuration questions in a **single `AskUserQuestion` call** with up to 4 questions:

**Question 1 — "What do you want to review?"**

| Option | Description |
|--------|-------------|
| Changes vs branch (Recommended) | Review changes against a base branch |
| Uncommitted changes | Review staged, unstaged, and untracked changes |
| Specific commit | Review changes introduced by a commit |

**Question 2 — "Include PR/issue context?"**

**If `PR_DETECTED=true`:**

| Option | Description |
|--------|-------------|
| Full context (Recommended) | Include PR/issue descriptions, all comments, and review feedback |
| Summary only | Include titles and key requirements only (~200 words) |
| No context | Review code changes only |

**If `PR_DETECTED=false`:**

| Option | Description |
|--------|-------------|
| Skip (Recommended) | Review code changes only |
| Provide PR number | Manually enter a PR number to use as context |
| Provide issue number | Manually enter an issue number to use as context |

**Question 3 — "Which model?"**

| Option | Description |
|--------|-------------|
| gpt-5.3-codex (Recommended) | Newest frontier model, best overall |
| gpt-5.2-codex | Previous generation frontier model |
| gpt-5.1-codex-max | Complex, long-running tasks (can run 24+ hours) |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

**Question 4 — "Review depth?"**

| Option | Description |
|--------|-------------|
| Single pass (Recommended) | One review pass (fastest) |
| Multi-pass (3) | Three passes, de-duplicated (most thorough) |
| Multi-pass (custom) | Specify number of passes |

Note: Multi-pass is most useful when PR/issue context is included.

### R2.5. Conditional Follow-Up (only if needed)

After processing answers from R2, check if any selections require additional input. If so, ask all follow-ups in a **single `AskUserQuestion` call** (up to 4 questions):

- **"Changes vs branch"** was selected → ask: "What is the base branch?" (default: `main`)
- **"Specific commit"** was selected → ask: "Enter the commit SHA"
- **"Provide PR number"** was selected → ask: "Enter the PR number"
  - Validate input is numeric: `echo "$NUM" | grep -qE '^[0-9]+$'`
  - If invalid, show error and ask again
  - Fetch PR: `gh pr view "$NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews --jq '.'`
  - Fetch linked issues and inline review comments as in R1
- **"Provide issue number"** was selected → ask: "Enter the issue number"
  - Validate input is numeric
  - Fetch issue: `gh issue view "$NUM" --json number,title,body,labels,comments --jq '.'`
  - Skip PR-specific data (no reviews to fetch)
- **"Multi-pass (custom)"** was selected → ask: "How many passes? (2-5)"
  - Validate numeric, clamp to range

If no follow-ups are needed (e.g., user chose "Uncommitted changes" + "Full context" or "Skip" + "Single pass"), proceed directly to R3.

Store all selections for use in R3.

### R3. Run Codex Review

Assemble and execute the command based on what to review and context settings.

#### If NO PR/Issue Context Selected

Use standard codex review commands (existing behavior):

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

#### If PR/Issue Context IS Included

Use `codex review -` (stdin mode) to keep the native review pipeline/rubric active while passing custom context. This preserves review quality that would be lost with `codex exec`.

**Step 1: Generate the diff**

Based on review type from R1:

- **Uncommitted:** `git diff HEAD && git diff --cached && git ls-files --others --exclude-standard`
- **Changes vs branch:** `git diff <branch>...HEAD`
- **Specific commit:** `git show <sha>`

**Step 2: Build context block**

**Full context format:**

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

**Summary only format:**

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

**If multi-pass was selected in R2.5**, run the review loop:

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

### Review Fix Detection

Before running Codex, detect if the prompt is addressing review feedback (e.g., contains phrases like "fix review comment", "address feedback", "fix the issue from review", or the prompt originates from an `/address-review` context). If a review-fix prompt is detected:

Append these instructions to the Codex prompt:

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

### Review Fix Fallback

After Codex completes, check if `_test.go` files were created or modified:

```bash
# Check both tracked changes and untracked new files
{ git diff --name-only HEAD; git ls-files --others --exclude-standard; } | grep '_test.go$'
```

If no test files were changed or created AND the fix modified testable behavior, Claude generates the missing tests following the same guidelines above.

### 1. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.3-codex | Newest frontier model, best overall |
| gpt-5.2-codex | Previous generation frontier model |
| gpt-5.1-codex-max | Complex, long-running tasks (can run 24+ hours) |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.3-codex`

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
