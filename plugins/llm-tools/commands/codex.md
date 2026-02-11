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

### R1. Select What to Review

Ask the user what to review:

| Option | Description |
|--------|-------------|
| Uncommitted changes | Review staged, unstaged, and untracked changes |
| Changes vs branch | Review changes against a base branch |
| Specific commit | Review changes introduced by a commit |

Default: `Changes vs branch`

**If "Changes vs branch":** Ask for the base branch name. Default: `main`

**If "Specific commit":** Ask for the commit SHA.

### R1.5. PR/Issue Context Detection

Before selecting a model, detect if PR/issue context is available for the current branch.

#### Step 1: Auto-detect PR

Run silently to check for a PR on the current branch:

```bash
PR_JSON=`gh pr view --json number,title,body,state,closingIssuesReferences,comments,reviews 2>/dev/null`
```

#### Step 2: Handle PR Detection Result

**If PR found (`$PR_JSON` is not empty):**

Extract and display PR summary:

```
Found PR for current branch:

**PR #<number>**: "<title>"
- State: <state>
- Comments: <count>
- Reviews: <count>
```

Check for linked issues using `closingIssuesReferences`. For each linked issue, fetch details:

```bash
REPO=`gh repo view --json nameWithOwner --jq '.nameWithOwner'`
PR_NUM=`echo "$PR_JSON" | jq -r '.number'`

# Get linked issue numbers
ISSUE_NUMS=`echo "$PR_JSON" | jq -r '.closingIssuesReferences[].number' 2>/dev/null`

# Fetch each linked issue
for NUM in $ISSUE_NUMS; do
  gh issue view "$NUM" --json number,title,body,labels,comments
done

# Fetch inline review comments
gh api "repos/$REPO/pulls/$PR_NUM/comments" --jq '.[] | {path, line, body, user: .user.login}' 2>/dev/null
```

Display linked issues if found:

```
**Linked Issues:**
- Issue #<num>: "<title>" (<labels>)
```

**If PR NOT found:**

Ask the user:

| Option | Description |
|--------|-------------|
| Skip context | Review code changes only (default) |
| Provide PR number | Manually enter a PR number to use as context |
| Provide issue number | Manually enter an issue number to use as context |

Default: `Skip context`

**If "Provide PR number":**
- Ask: "Enter the PR number:"
- Validate input is numeric: `echo "$NUM" | grep -qE '^[0-9]+$'`
- If invalid, show error and ask again
- Fetch PR: `gh pr view "$NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews`
- Continue to fetch linked issues as above

**If "Provide issue number":**
- Ask: "Enter the issue number:"
- Validate input is numeric
- Fetch issue: `gh issue view "$NUM" --json number,title,body,labels,comments`
- Skip PR-specific data (no reviews to fetch)

#### Step 3: Context Inclusion Prompt

**If PR or issue was found/provided:**

Ask the user:

| Option | Description |
|--------|-------------|
| Full context | Include PR/issue descriptions, all comments, and review feedback (recommended) |
| Summary only | Include titles and key requirements only (~200 words) |
| No context | Proceed with code changes only |

Default: `Full context`

Store the selection for use in R3.

**If neither PR nor issue found and user chose "Skip context":**

Proceed directly to R2 with no context.

### R2. Select Model

Ask the user which model to use:

| Model | Best For |
|-------|----------|
| gpt-5.3-codex | Newest frontier model, best overall |
| gpt-5.2-codex | Previous generation frontier model |
| gpt-5.1-codex-max | Complex, long-running tasks (can run 24+ hours) |
| gpt-5.1-codex-mini | Simple tasks, cost-efficient |

Default: `gpt-5.3-codex`

### R2.5. Select Review Depth

**If PR/issue context is included**, ask the user:

| Option | Description |
|--------|-------------|
| Single pass | One review pass (default, fastest) |
| Multi-pass (3) | Three passes, de-duplicated (recommended for thorough review) |
| Multi-pass (custom) | Specify number of passes |

Default: `Single pass`

**If "Multi-pass (custom)":** Ask: "How many passes? (2-5)" — validate numeric, clamp to range.

Store the pass count for use in R3.

**If no PR/issue context is selected**, skip this prompt entirely (single pass is implicit).

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

**Pass 2 through N:** Build an augmented prompt that appends a "Previous Findings" section to the original context block:

```text
<original context block with diff>

---

## Previous Findings (from passes 1 through <current-1>)

<concatenated findings from all prior passes>

---

## Instructions for This Pass

You have already identified the findings listed above. For this pass, ONLY report NET-NEW findings that are NOT covered by the previous findings. Focus on issues that were missed, edge cases, or deeper analysis.

If there are no new findings to report, respond with exactly: NO_NEW_FINDINGS
```

Execute:

```bash
codex review -c model=<model> - <<'EOF'
<augmented context block>
EOF
```

Capture output as `PASS_<N>_FINDINGS`.

**Early stop:** If the output contains `NO_NEW_FINDINGS` or is substantively empty (fewer than 20 characters of content after stripping whitespace), stop the loop immediately.

**After all passes complete:** Proceed to de-duplication.

#### De-Duplicate Findings

After collecting findings from all passes, de-duplicate before presenting results:

1. Parse each finding to extract: file path, line number/range, finding title/summary
2. Normalize for comparison: lowercase titles, collapse whitespace, treat line numbers within ±3 lines as the same location
3. Group by (file path, normalized line range, normalized title)
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
