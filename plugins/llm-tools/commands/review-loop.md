---
argument-hint: "[--llm codex|gemini|ollama] [--max-passes <n>] [scope hint]"
description: "Iterative LLM review loop: review, fix, verify, repeat until clean"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion"]
---

# Iterative LLM Review Loop

!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "review-loop" "REVIEW_CLEAN" 25`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: LLM to use for reviews. Options: `codex` (default), `gemini`, `ollama`
- `--max-passes <n>`: Maximum review passes before stopping (default: 5)
- Remaining text: scope hint (e.g., "focus on error handling")

Store as `LLM_CHOICE`, `MAX_PASSES`, and `SCOPE_HINT`.

## 2. Prerequisite Check

Verify the selected LLM CLI is installed. Fail fast with install instructions if not found.

```bash
# Check based on LLM_CHOICE
if [ "$LLM_CHOICE" = "codex" ]; then
  command -v codex >/dev/null 2>&1 || { echo "codex not found. Install: npm install -g @openai/codex"; exit 1; }
elif [ "$LLM_CHOICE" = "gemini" ]; then
  command -v gemini >/dev/null 2>&1 || { echo "gemini not found. Install: npm install -g @google/gemini-cli"; exit 1; }
elif [ "$LLM_CHOICE" = "ollama" ]; then
  command -v ollama >/dev/null 2>&1 || { echo "ollama not found. Install: brew install ollama"; exit 1; }
fi
```

If the check fails, report the error, clean up the loop state file to prevent stale re-entry, and stop:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "review-loop"
```

Do NOT continue the loop. Output `<done>REVIEW_CLEAN</done>` to signal completion.

## 3. Re-entry Check

Read the loop state file at `.claude/review-loop.loop.local.md`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".claude/review-loop.loop.local.md"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry from the stop-hook. Skip to the corresponding phase:

- `reviewing` → go to Step 5
- `fixing` → go to Step 7
- `verifying` → go to Step 8

If `PHASE` is empty or unset, this is a fresh start. Continue to Step 4.

## 4. Detect Review Scope

### 4a. Silent PR Auto-Detection

Before asking any questions, silently detect PR context using multiple strategies:

**Strategy 1 — Current branch:**

```bash
PR_JSON=`gh pr view --json number,title,body,state,closingIssuesReferences --jq '.' 2>/dev/null`
```

**Strategy 2 — Match HEAD commit against open PRs:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state open --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences 2>/dev/null`
  fi
fi
```

**Strategy 3 — Check merged/closed PRs too:**

```bash
if [ -z "$PR_JSON" ]; then
  HEAD_SHA=`git rev-parse HEAD 2>/dev/null`
  PR_NUM=`gh pr list --search "$HEAD_SHA" --state all --limit 5 --json number --jq '.[0].number' 2>/dev/null`
  if [ -n "$PR_NUM" ] && [ "$PR_NUM" != "null" ]; then
    PR_JSON=`gh pr view "$PR_NUM" --json number,title,body,state,closingIssuesReferences 2>/dev/null`
  fi
fi
```

If a PR was found, display a brief summary.

### 4b. Ask User for Review Scope

Use a **single `AskUserQuestion` call** with these questions:

**Question 1 — "What do you want to review?"**

| Option | Description |
|--------|-------------|
| Changes vs branch (Recommended) | Review changes against a base branch (default: `main`) |
| Uncommitted changes | Review staged, unstaged, and untracked changes |
| Specific files | Review only specific files or directories |

**Question 2 — "Which model?"**

Show model options based on `LLM_CHOICE`:

**If codex:**

| Model | Description |
|-------|-------------|
| gpt-5.4 (Recommended) | Latest frontier model, best overall |
| gpt-5.4-pro | Maximum performance on complex tasks |
| gpt-5.3-codex | Previous generation frontier model |
| gpt-5.1-codex-mini | Cost-efficient |

**If gemini:**

| Model | Description |
|-------|-------------|
| gemini-2.5-pro (Recommended) | Most capable |
| gemini-2.5-flash | Faster, cost-efficient |

**If ollama:**

| Model | Description |
|-------|-------------|
| codellama (Recommended) | Code-specialized |
| llama3 | General purpose |
| deepseek-coder | Code-specialized |
| Custom | Enter model name |

### 4c. Conditional Follow-Up

If "Changes vs branch" was selected, ask for the base branch (default: `main`).
If "Specific files" was selected, ask for the file paths.
If "Custom" model was selected, ask for the model name.

Store all selections: `REVIEW_SCOPE`, `BASE_BRANCH`, `MODEL`, `FILE_PATHS`.

Initialize pass counter: `PASS=0`.

## 5. Review Phase

Set phase to `reviewing`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".claude/review-loop.loop.local.md" "reviewing"
```

Increment pass counter: `PASS=$((PASS + 1))`

### 5a. Generate Diff

Based on `REVIEW_SCOPE`:

- **Changes vs branch:** `git diff ${BASE_BRANCH}...HEAD`
- **Uncommitted changes:** `git diff HEAD` combined with `git diff --cached` and `git ls-files --others --exclude-standard`
- **Specific files:** `git diff ${BASE_BRANCH}...HEAD -- <file_paths>`

### 5b. Run LLM Review

Execute the review based on `LLM_CHOICE`:

**Codex:**

```bash
# For changes vs branch (native mode):
codex review --base "$BASE_BRANCH" -c model="$MODEL"

# For uncommitted:
codex review --uncommitted -c model="$MODEL"

# For specific files or when scope hint is provided, use stdin:
DIFF=$(git diff ${BASE_BRANCH}...HEAD -- <files>)
echo "$DIFF" | codex review -c model="$MODEL" - <<EOF
$DIFF

## Review Instructions
${SCOPE_HINT:+Focus area: $SCOPE_HINT}
Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND
EOF
```

**Gemini:**

```bash
DIFF=$(git diff ${BASE_BRANCH}...HEAD)
gemini -m "$MODEL" <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

${SCOPE_HINT:+Focus area: $SCOPE_HINT}

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

**Ollama:**

```bash
DIFF=$(git diff ${BASE_BRANCH}...HEAD)
ollama run "$MODEL" <<EOF
Review the following code changes for bugs, security issues, performance problems, and best practice violations.

${SCOPE_HINT:+Focus area: $SCOPE_HINT}

Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND

\`\`\`diff
$DIFF
\`\`\`
EOF
```

Capture the output as `FINDINGS`.

## 6. Parse Findings

After capturing the LLM review output:

- If output (trimmed) equals exactly `NO_ISSUES_FOUND` or has fewer than 20 characters of content:
  - If `PASS == 1`: Ask user to confirm the scope is correct (first-pass clean review may indicate wrong scope). If user confirms scope is fine → output `<done>REVIEW_CLEAN</done>` and stop.
  - If `PASS > 1`: Clean review after fixes. Output summary and `<done>REVIEW_CLEAN</done>`.
- Otherwise: Extract structured findings from the output. Display findings to user with pass number.

**Filter bot noise:** Silently discard any finding that contains usage-limit or quota messages (e.g., "reached your Codex usage limits", "usage limits for code reviews", "see your limits").

## 7. Fix Phase

Set phase to `fixing`:

```bash
set_loop_phase ".claude/review-loop.loop.local.md" "fixing"
```

For each finding from Step 6:

1. Read the relevant file and surrounding code context
2. Evaluate the finding — is it valid and actionable?
3. If valid: make the fix using Edit tool
4. If not valid or intentionally skipped: record the reason
5. For testable fixes (changes observable behavior): generate a corresponding test
   - Check for existing `_test.go` / `_test.ts` / `test_*.py` files
   - If table-driven tests exist, add a new case
   - If no test exists, create one following project conventions
   - Verify the new test passes

Track counts: `FIXED`, `SKIPPED` (with reasons).

## 8. Verify Phase

Set phase to `verifying`:

```bash
set_loop_phase ".claude/review-loop.loop.local.md" "verifying"
```

Auto-detect project type and run appropriate verification:

**Go** (go.mod exists):

```bash
go build ./...
go test ./...
golangci-lint run 2>/dev/null || true  # optional: may not be installed
```

**Node/TypeScript** (package.json exists):

```bash
npm run build  # fail if build breaks
npm test       # fail if tests break
npm run lint 2>/dev/null || true  # optional: lint script may not exist
```

**Rust** (Cargo.toml exists):

```bash
cargo build
cargo test
cargo clippy 2>/dev/null || true  # optional: may not be installed
```

**Python** (pyproject.toml or setup.py exists):

```bash
pytest 2>/dev/null || python -m pytest  # fail if tests break
ruff check . 2>/dev/null || flake8 . 2>/dev/null || true  # optional: linter may not be installed
```

**Fallback:** If no project type detected, ask the user what verify command to run.

If any verification fails:
1. Analyze the failure
2. Fix the issue
3. Re-run the failing verification
4. Repeat until all verifications pass

## 9. Commit Fixes

Stage only the files that were fixed in this pass and commit. Do NOT use `git add -A` as it may sweep in unrelated working-tree changes:

```bash
git add <list of files modified during fix phase>
git commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
```

Track which files were edited during the fix phase (Step 7) and only stage those specific files.

Display summary for this pass:
- Findings reported by LLM
- Findings fixed
- Findings skipped (with reasons)
- Files changed
- Verification status

## 10. Loop Decision

Check if we should continue:

- If `PASS >= MAX_PASSES`:
  - Display overall summary (total passes, total findings addressed, total skipped, files changed)
  - Ask user: "Max passes reached. Continue for another round or stop?"
  - If stop → output `<done>REVIEW_CLEAN</done>`
  - If continue → reset `MAX_PASSES` to `MAX_PASSES + current value` and go to Step 5
- Otherwise:
  - Go to Step 5 (next review pass)

## Completion

When outputting completion, always include a summary:

```
## Review Loop Complete

- **LLM:** <llm> (<model>)
- **Total passes:** <n>
- **Findings addressed:** <n>
- **Findings skipped:** <n> (with reasons listed)
- **Files changed:** <list>
- **All verifications passed:** yes/no
```

Then output the completion promise:

```
<done>REVIEW_CLEAN</done>
```

## Important Notes

- **Bot message filtering:** When processing LLM review output, silently discard any content about external service usage limits or quota messages. These are irrelevant to the local review.
- **De-duplication across passes:** If a finding from a previous pass appears again (same file, same line, same issue), skip it — it was already addressed or intentionally skipped.
- **Phase re-entry:** The stop-hook will re-feed this command if the session exits mid-loop. The phase check in Step 3 ensures we resume at the correct point.
- **Cancel:** Users can run `/cancel-loop review-loop` at any time to cleanly exit the loop.
