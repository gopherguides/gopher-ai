# Codex — Review Flow (R1–R4)

Loaded by `commands/codex.md` when the prompt is review-oriented. Owns the
full review pipeline: configuration, base-branch detection, PR/issue context,
execution paths, and result formatting.

## R1. Review Configuration

### If `INTERACTIVE_MODE` is `false` (default — no `--ask` flag)

Use recommended defaults without prompting. Display a brief configuration summary:

```
Review config (defaults — add --ask to customize):
  Review type:  Changes vs branch
  Context:      Auto-detect
  Model:        Provider default
  Effort:       high
  Depth:        Exhaustive
```

Store: review type = "Changes vs branch", context = "Auto-detect", model = "", depth = "Exhaustive". An empty model means Codex CLI selects its provider default, including any user-configured `~/.codex/config.toml` model override. Reasoning effort is always `high` (pinned via `-c model_reasoning_effort="high"` on every codex invocation — not user-configurable). Proceed directly to R1.5.

### If `INTERACTIVE_MODE` is `true` (`--ask` flag provided)

**Do NOT run any `gh` or `git` commands before asking the user questions.** PR detection is deferred until after the user requests context. This avoids wasting tokens on `gh pr view` calls when the user doesn't need PR context. Exception: lightweight branch detection (`gh pr view --json baseRefName`, `git remote show origin`) is permitted in R1.5 after R1 answers are collected — these are fast, single-field queries that avoid blocking the user.

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
| Provider default (Recommended) | Let Codex CLI choose the latest recommended Codex model |
| Custom model ID | Enter an exact model ID; only this choice passes `-m` or `-c model=...` |

**Question 4 — "Review depth?"**

| Option | Description |
|--------|-------------|
| Exhaustive (Recommended) | `codex exec` with structured output — returns ALL findings in one pass |
| Single pass | One `codex review` pass (fastest, but limited to 2-3 findings) |
| Multi-pass (3) | Three `codex review` passes, de-duplicated |
| Multi-pass (custom) | Specify number of `codex review` passes |

Note: Exhaustive mode uses `codex exec --output-schema` to bypass the 2-3 finding limit of `codex review`. Multi-pass is available as a fallback but is less effective than exhaustive mode.

## R1.5. Conditional Follow-Up

### If `INTERACTIVE_MODE` is `false` (default)

Since defaults are "Changes vs branch" + "Auto-detect" + "Exhaustive", the only follow-up needed is base branch auto-detection. Run silently:

```bash
PR_JSON=`gh pr view --json baseRefName --jq '.' 2>/dev/null || echo ""`
if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "" ]; then
  BASE_BRANCH=`echo "$PR_JSON" | jq -r '.baseRefName'`
else
  BASE_BRANCH=`(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | rg 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main"`
fi
```

Display: "Detected base branch: `$BASE_BRANCH`". Proceed directly to R2.

### If `INTERACTIVE_MODE` is `true`

After processing answers from R1, check if any selections require additional input. If so, ask all follow-ups in a **single `AskUserQuestion` call** (up to 4 questions):

- **"Changes vs branch"** was selected → silently auto-detect the base branch instead of asking:

  ```bash
  PR_JSON=`gh pr view --json baseRefName --jq '.' 2>/dev/null || echo ""`
  if [ -n "$PR_JSON" ] && [ "$PR_JSON" != "" ]; then
    BASE_BRANCH=`echo "$PR_JSON" | jq -r '.baseRefName'`
  else
    BASE_BRANCH=`(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' | grep .) || (git remote show -n origin 2>/dev/null | rg 'HEAD branch' | sed 's/.*: //' | grep .) || echo "main"`
  fi
  ```

  Display: "Detected base branch: `$BASE_BRANCH`". If the user corrects it (e.g., "use `develop`"), update `BASE_BRANCH` accordingly.

- **"Specific commit"** was selected → ask: "Enter the commit SHA"
- **"Provide PR number"** was selected → ask: "Enter the PR number"
  - Validate input is numeric: `echo "$NUM" | grep -qE '^[0-9]+$'`
  - If invalid, show error and ask again
- **"Provide issue number"** was selected → ask: "Enter the issue number"
  - Validate input is numeric
- **"Multi-pass (custom)"** was selected → ask: "How many passes? (2-5)"
  - Validate numeric, clamp to range

If the only follow-up was the base branch (i.e., "Changes vs branch" selected with no other selections requiring input), the auto-detection above handles it — skip `AskUserQuestion` and proceed directly to R2. The detected branch is displayed so the user can see it and correct it if needed before the review runs.

If no follow-ups are needed (e.g., user chose "No context" + "Single pass"), proceed directly to R2.

Store all selections for use in R2.

## R2. Fetch PR/Issue Context (only if requested)

**Only run this step if the user selected "Auto-detect", "Provide PR number", or "Provide issue number" in R1.** If "No context", skip entirely to R3.

### If "No context" was selected

Skip this entire section. Set `PR_DETECTED=false`. Proceed to R3.

### If "Provide PR number" was selected

```bash
PR_JSON=$(gh pr view "$NUM" --json number,title,body,state,closingIssuesReferences,comments,reviews --jq '.' 2>/dev/null)
```

If successful, fetch linked issues and inline comments (see "Fetch PR details" below). Record `PR_DETECTED=true`.

### If "Provide issue number" was selected

```bash
gh issue view "$NUM" --json number,title,body,labels,comments --jq '.' 2>/dev/null
```

Skip PR-specific data. Record `ISSUE_DETECTED=true` and `PR_DETECTED=false`.

### If "Auto-detect" was selected

**Early bail-out on default branch:** Before running any `gh` commands, check the current branch:

```bash
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' | grep . || echo "main")
```

If `$CURRENT_BRANCH` equals `$DEFAULT_BRANCH`: skip the automatic strategies (they would match unrelated merged PRs). **If `INTERACTIVE_MODE` is `false`:** silently set `PR_DETECTED=false` and proceed to R3 without prompting. **If `INTERACTIVE_MODE` is `true`:** ask the user via `AskUserQuestion`: "On default branch — auto-detect skipped. Enter a PR number (e.g. `123`), issue number (e.g. `#45`), or press Enter to proceed without context." If the user provides input prefixed with `#`, strip the `#` and use the "Provide issue number" path. Otherwise validate it is numeric (`echo "$INPUT" | grep -qE '^[0-9]+$'`). If invalid, re-prompt. If valid, fetch it. If empty/Enter, set `PR_DETECTED=false`.

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

**If no PR found after all strategies:** **If `INTERACTIVE_MODE` is `false`:** silently set `PR_DETECTED=false` and proceed to R3 without prompting. **If `INTERACTIVE_MODE` is `true`:** ask the user via `AskUserQuestion`: "No PR found for current branch. Enter a PR number (e.g. `123`), issue number (e.g. `#45`), or press Enter to proceed without context." Same parsing rules as above.

### Fetch PR details (shared by Auto-detect and Provide PR number)

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

## R3. Run Codex Review

Assemble and execute the command based on review depth selection from R1.

**IMPORTANT:** Check exhaustive mode FIRST, regardless of context selection. Exhaustive mode works with or without PR/issue context.

### Exhaustive Mode

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
- `{PR_CONTEXT}` ← if `PR_DETECTED` is `true`, include PR title, body, linked issues, and review comments. If `ISSUE_DETECTED` is `true` (but no PR), include issue title, body, labels, and comments instead. If neither, leave empty

**Step 3: Execute with structured output**

Write the assembled prompt to a temp file to avoid heredoc expansion issues with special characters in diffs:

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt-XXXXXX)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"
MODEL_ARGS=()
if [ -n "$MODEL" ]; then
  MODEL_ARGS=(-m "$MODEL")
fi

REVIEW_JSON=$($CODEX_CMD exec "${MODEL_ARGS[@]}" -s read-only \
  -c model_reasoning_effort="high" \
  --output-schema "${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json" \
  - < "$PROMPT_FILE")
# Strip codex exec headers (version/config info printed before JSON)
REVIEW_JSON=$(printf '%s\n' "$REVIEW_JSON" | awk '/^\{/{found=1} found{print}')
# Guard: if stripping removed all output, codex exec returned no JSON
if [ -z "$REVIEW_JSON" ]; then
  echo "WARNING: $CODEX_CMD exec produced no JSON output after header stripping"
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

### Single/Multi-pass — NO PR/Issue Context

Use standard codex review commands:

Build optional model config first. Leave `MODEL_CONFIG` empty for provider default:

```bash
MODEL_CONFIG=()
if [ -n "$MODEL" ]; then
  MODEL_CONFIG=(-c "model=$MODEL")
fi
```

**For uncommitted changes:**

```bash
$CODEX_CMD review --uncommitted "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high"
```

**For changes vs branch:**

```bash
$CODEX_CMD review --base <branch> "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high"
```

**For specific commit:**

```bash
$CODEX_CMD review --commit <sha> "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high"
```

Capture output as `FINDINGS`. Skip to R4 (or multi-pass loop below).

### Single/Multi-pass — PR/Issue Context Included

Use `codex review -` (stdin mode) with the native review pipeline.

**Step 1: Generate the diff** (same logic as Exhaustive Step 1 above; for uncommitted, use `git diff HEAD && git diff --cached && git ls-files --others --exclude-standard`).

**Step 2: Build context block**

Include PR/issue context fetched in R2. Only include sections for which data exists.

**Size guard:** Before assembling, estimate the total context size (PR body + issue bodies + comments). If the combined text exceeds ~4000 characters, use the **Summary format** to avoid crowding the diff out of the model context. Otherwise use the **Full format**.

**Full format — PR context** (use when `PR_DETECTED` is `true`):

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

**Full format — Issue-only context** (use when `ISSUE_DETECTED` is `true` but `PR_DETECTED` is `false`):

```text
## Issue Context

### Issue #<number>: <title>
**Labels:** <labels>
**Description:**
<issue body>

**Issue Comments:**
- @<user>: <comment body>

---

## Code Changes

\`\`\`diff
<diff output>
\`\`\`

---

## Review Instructions

Review the code changes above against the requirements from the issue.

Specifically:
1. Verify the implementation addresses the stated requirements
2. Identify any requirements from the issue that may be missing
3. Flag any code that contradicts the original intent
4. Suggest improvements aligned with the stated goals
```

**Summary format** (used when context exceeds ~4000 chars):

**If PR context is available:**

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

**If only issue context is available (no PR):**

```text
## Issue Context (Summary)

**Issue #<number>:** <title>
**Labels:** <labels>
**Key Requirements:** <first 300 chars of issue body>

**Issue Discussion:**
- <summarized key points from issue comments>

---

## Code Changes

\`\`\`diff
<diff output>
\`\`\`

---

Review these changes against the requirements above. Ensure the implementation addresses the issue.
```

**Step 3: Execute review via stdin**

#### Single Pass (or no multi-pass selected)

```bash
MODEL_CONFIG=()
if [ -n "$MODEL" ]; then
  MODEL_CONFIG=(-c "model=$MODEL")
fi

$CODEX_CMD review "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high" - <<'EOF'
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
$CODEX_CMD review "${MODEL_CONFIG[@]}" -c model_reasoning_effort="high" - <<'EOF'
<augmented context block>
EOF
```

Capture output as `PASS_<N>_FINDINGS`.

**Early stop:** If the output, after stripping leading/trailing whitespace, equals exactly `NO_NEW_FINDINGS` or is substantively empty (fewer than 20 characters of content), stop the loop immediately. Do not match substring occurrences — only an exact trimmed match triggers early stop.

**After all passes complete:** Proceed to de-duplication.

### De-Duplicate Findings

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

## R4. Report Results

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

**If "Post to PR":** format the findings as a markdown comment and post. For multi-pass reviews, use the aggregated de-duplicated output:

```bash
gh pr comment <pr_number> --body "<formatted FINDINGS>"
```

**If no context was included:** ask if they want to run a follow-up review or switch to exec mode. For follow-ups, use: `codex resume --last`.
