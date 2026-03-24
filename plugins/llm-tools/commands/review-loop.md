---
argument-hint: "[--llm codex|gemini|ollama] [--max-passes <n>] [--quick] [scope hint]"
description: "Iterative LLM review loop: review, fix, verify, repeat until clean"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent"]
---

# Iterative LLM Review Loop

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "review-loop" "REVIEW_CLEAN" 25 "" '{"reviewing":"Resume the review-fix-verify cycle. Run the next review pass.","fixing":"Continue fixing: address remaining review findings, then verify.","verifying":"Continue verification: run build, test, and lint on fixes."}'; fi`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: LLM to use for reviews. Options: `codex` (default), `gemini`, `ollama`
- `--max-passes <n>`: Maximum review passes before stopping (default: 5)
- `--quick`: Use lightweight `codex review` instead of exhaustive `codex exec` (faster but limited to 2-3 findings per pass). Only applies when `--llm codex`.
- Remaining text: scope hint (e.g., "focus on error handling")

Store as `LLM_CHOICE`, `MAX_PASSES`, `QUICK_MODE` (default: `false`), and `SCOPE_HINT`.

**Persist arguments to state file** for re-entry recovery. After parsing, merge these fields into `.claude/review-loop.loop.local.json` using `jq`:

```bash
STATE_FILE=".claude/review-loop.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg args "$ARGUMENTS" --argjson pass 0 --arg quick_mode "$QUICK_MODE" \
   '. + {args: $args, pass: $pass, quick_mode: $quick_mode}' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

This ensures stop-hook re-entry can restore the original configuration (including `QUICK_MODE`).

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

Read the loop state file at `.claude/review-loop.loop.local.json`:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".claude/review-loop.loop.local.json"
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE"
fi
```

If `PHASE` is set (non-empty), this is a re-entry from the stop-hook. Recover state from the persisted fields using `jq`:

1. Read `args` field and re-parse to restore `LLM_CHOICE`, `MAX_PASSES`, `QUICK_MODE`, `SCOPE_HINT`
2. Read `pass` field via `jq -r '.pass // 0' "$STATE_FILE"` to restore the current pass count
3. Read `scope`, `base_branch`, `model`, `file_paths`, `quick_mode` fields via `jq -r '.field // empty' "$STATE_FILE"` to restore `REVIEW_SCOPE`, `BASE_BRANCH`, `MODEL`, `FILE_PATHS`, `QUICK_MODE`

Then skip to the corresponding phase:

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
If "Specific files" was selected, ask for the base branch (default: `main`) AND the file paths.
If "Custom" model was selected, ask for the model name.

Store all selections: `REVIEW_SCOPE`, `BASE_BRANCH`, `MODEL`, `FILE_PATHS`.

**Persist scope/model to state file** for re-entry recovery. Merge these fields into `.claude/review-loop.loop.local.json`:

```bash
STATE_FILE=".claude/review-loop.loop.local.json"
TMP="$STATE_FILE.tmp"
jq --arg scope "$REVIEW_SCOPE" --arg base_branch "$BASE_BRANCH" \
   --arg model "$MODEL" --arg file_paths "${FILE_PATHS:-}" \
   '. + {scope: $scope, base_branch: $base_branch, model: $model, file_paths: $file_paths}' \
   "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

The `pass:` field in the state file was initialized to 0 in Step 1.

## 5. Review Phase

Set phase to `reviewing` and increment the `pass:` field in the state file:

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".claude/review-loop.loop.local.json" "reviewing"
# Increment pass counter in state file (read current value, increment, write back)
```

Read the updated `pass:` value from the state file into `PASS` for use in this pass.

### 5a. Generate Diff

Based on `REVIEW_SCOPE`:

- **Changes vs branch:** `git diff ${BASE_BRANCH}...HEAD`
- **Uncommitted changes:** `git diff HEAD` (includes both staged and unstaged changes vs HEAD — do NOT also add `git diff --cached` as that duplicates staged hunks). For untracked files, use `git ls-files --others --exclude-standard` to get paths, then include their full content (e.g., `cat <file>`) in the diff section so new files are actually reviewed by `codex exec`.
- **Specific files:** `git diff ${BASE_BRANCH}...HEAD -- <file_paths>`

### 5b. Run LLM Review

Execute the review based on `LLM_CHOICE`:

**Codex (default — exhaustive mode via `codex exec`):**

When `QUICK_MODE` is `false` (the default), use `codex exec` with a structured output schema. This bypasses the 2-3 finding limit of `codex review` and returns ALL findings as structured JSON.

1. Read the prompt template:

```bash
PROMPT_TEMPLATE=$(cat "${CLAUDE_PLUGIN_ROOT}/prompts/codex-review.md")
```

2. Build the prompt by replacing `{PLACEHOLDER}` tokens:

- `{DIFF}` ← diff from Step 5a
- `{SCOPE_HINT}` ← if `SCOPE_HINT` is set, render as `## Specific Focus Area\n$SCOPE_HINT`; otherwise empty string
- `{REPO_GUIDELINES}` ← auto-detect `AGENTS.md` in repo root; if found, render as `## Repository Review Guidelines\n$(cat AGENTS.md)`; else check `CLAUDE.md`; otherwise empty string
- `{PR_CONTEXT}` ← if PR was detected in Step 4a, render PR number, title, body, and linked issues; otherwise empty string

3. Write the assembled prompt to a temp file (avoids heredoc expansion issues with special characters in diffs):

```bash
PROMPT_FILE=$(mktemp /tmp/codex-review-prompt.XXXXXX.md)
echo "$ASSEMBLED_PROMPT" > "$PROMPT_FILE"
REVIEW_JSON=$(codex exec -m "$MODEL" -s read-only \
  --output-schema "${CLAUDE_PLUGIN_ROOT}/schemas/codex-review.json" \
  - < "$PROMPT_FILE")
rm -f "$PROMPT_FILE"
```

4. Validate JSON was returned. If `codex exec` returns non-JSON or empty output, this is a review failure — do NOT fall through to the free-text clean-review path (which would treat empty output as `NO_ISSUES_FOUND`). Instead, warn the user: "Codex exec returned invalid output. Review did not complete." Ask whether to retry the pass, fall back to `codex review` for this pass, or skip the review.

**Codex (quick mode — `--quick` flag):**

When `QUICK_MODE` is `true`, use the standard `codex review` command. This is faster but limited to 2-3 findings per pass:

```bash
# For changes vs branch:
codex review --base "$BASE_BRANCH" -c model="$MODEL"

# For uncommitted:
codex review --uncommitted -c model="$MODEL"

# For specific files or when scope hint is provided, use stdin:
DIFF=$(git diff ${BASE_BRANCH}...HEAD -- <files>)
codex review -c model="$MODEL" - <<EOF
$DIFF

## Review Instructions
${SCOPE_HINT:+Focus area: $SCOPE_HINT}
Report each finding with: file path, line number, severity (error/warning/suggestion), and description.
If there are no issues, respond with exactly: NO_ISSUES_FOUND
EOF
```

Capture output as free-text `FINDINGS`.

**Gemini:**

Use the `DIFF` generated in Step 5a (scope-aware), not a hardcoded branch diff.

```bash
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

Use the `DIFF` generated in Step 5a (scope-aware), not a hardcoded branch diff.

```bash
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

### 6a. Structured JSON (codex exec mode)

When `LLM_CHOICE` is `codex` and `QUICK_MODE` is `false` and `CODEX_EXEC_FALLBACK` is not `true`:

1. Validate JSON: `echo "$REVIEW_JSON" | jq empty 2>/dev/null`. If invalid, log a warning and fall through to Step 6b with `FINDINGS="$REVIEW_JSON"`.

2. Extract and filter findings:

```bash
OVERALL=$(echo "$REVIEW_JSON" | jq -r '.overall_correctness')
OVERALL_EXPLANATION=$(echo "$REVIEW_JSON" | jq -r '.overall_explanation')
OVERALL_CONFIDENCE=$(echo "$REVIEW_JSON" | jq -r '.overall_confidence_score')
```

3. Filter low-confidence noise FIRST — discard findings with `confidence_score < 0.3`:

```bash
FILTERED_JSON=$(echo "$REVIEW_JSON" | jq '{
  findings: [.findings[] | select(.confidence_score >= 0.3)],
  overall_correctness: .overall_correctness,
  overall_explanation: .overall_explanation,
  overall_confidence_score: .overall_confidence_score
}')
FINDING_COUNT=$(echo "$FILTERED_JSON" | jq '.findings | length')
```

4. Check for clean review AFTER filtering (so filtered-to-zero also triggers clean path):

If `FINDING_COUNT == 0` and `OVERALL` is `"patch is correct"`:
   - If `PASS == 1`: Ask user to confirm scope is correct. If confirmed → output `<done>REVIEW_CLEAN</done>`.
   - If `PASS > 1`: Clean verification pass. Output summary and `<done>REVIEW_CLEAN</done>`.

If `FINDING_COUNT == 0` but `OVERALL` is `"patch is incorrect"`: display `overall_explanation` as a warning but treat as clean (no actionable findings survived filtering).

5. Sort by priority (0 first), then confidence (highest first).

6. Display as formatted table:

```
## Review Findings (Pass $PASS) — $FINDING_COUNT issues

| # | Priority | Category | File | Lines | Title | Confidence |
|---|----------|----------|------|-------|-------|------------|
| 1 | P0 | correctness | api/handler.go | 42-45 | Nil pointer on empty response | 0.95 |
```

Display `overall_explanation` as a summary below the table.

7. **De-duplicate across passes:** Compare `(file_path, line_range.start, normalized title)` against previous-pass findings stored in state file. Skip duplicates.

8. Store findings in state file for de-duplication and re-entry:

```bash
jq --argjson f "$FILTERED_JSON" --arg key "findings_pass_$PASS" \
  '.[$key] = $f.findings' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
```

### 6b. Free-text (codex quick mode / gemini / ollama)

After capturing the LLM review output as `FINDINGS`:

- If output (trimmed) equals exactly `NO_ISSUES_FOUND` or has fewer than 20 characters of content:
  - If `PASS == 1`: Ask user to confirm the scope is correct (first-pass clean review may indicate wrong scope). If user confirms scope is fine → output `<done>REVIEW_CLEAN</done>` and stop.
  - If `PASS > 1`: Clean review after fixes. Output summary and `<done>REVIEW_CLEAN</done>`.
- Otherwise: Extract structured findings from the output. Display findings to user with pass number.

**Filter bot noise:** Silently discard any finding that contains usage-limit or quota messages (e.g., "reached your Codex usage limits", "usage limits for code reviews", "see your limits").

## 7. Fix Phase

Set phase to `fixing`:

```bash
set_loop_phase ".claude/review-loop.loop.local.json" "fixing"
```

### Parallel Fix Dispatch (when 3+ findings target different files)

When structured findings (codex exec mode) contain 3 or more findings targeting **different files**, dispatch parallel Implementer subagents for faster resolution:

1. **Group findings by file** — findings in the same file must be handled sequentially (one subagent per file group)
2. **For each file group**, dispatch an Agent subagent (sonnet) with this prompt:
   - "You are fixing review findings in `{FILE_PATH}`. Working directory: `{PROJECT_ROOT}`."
   - Include all findings for that file (title, body, line range, priority, category)
   - "For each finding: read the file, evaluate validity, fix if valid (skip if not), generate test if testable. Report STATUS, FILES_CHANGED, TEST_RESULTS, SKIPPED findings with reasons."
3. **Dispatch all file-group agents in parallel** using `run_in_background: true`
4. **Collect results** — aggregate FIXED and SKIPPED counts across all subagents
5. **Proceed to Step 8** (Verify Phase) with combined results

**Fall back to sequential processing** (steps 7a/7b below) when:
- Fewer than 3 findings (subagent overhead not justified)
- Findings are free-text (not structured JSON — harder to distribute)
- All findings target the same file

### 7a. Structured findings (codex exec mode)

When findings are structured JSON from Step 6a, iterate using `jq` and process in priority order (P0 first):

```bash
for i in $(seq 0 $((FINDING_COUNT - 1))); do
  FILE=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].code_location.file_path")
  START=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].code_location.line_range.start")
  END=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].code_location.line_range.end")
  TITLE=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].title")
  BODY=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].body")
  PRIORITY=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].priority")
  CATEGORY=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].category")
  CONFIDENCE=$(echo "$FILTERED_JSON" | jq -r ".findings[$i].confidence_score")
done
```

For each finding:

1. Read `$FILE` lines `$START` to `$END` plus surrounding context
2. Evaluate: Is this valid? Cross-reference with category and confidence.
3. Auto-skip findings with `priority == 3` AND `confidence < 0.5` (nit-level noise)
4. If valid: make the fix using Edit tool
5. If not valid or intentionally skipped: record the reason
6. For testable fixes (changes observable behavior): generate a corresponding test
   - Check for existing `_test.go` / `_test.ts` / `test_*.py` files
   - If table-driven tests exist, add a new case
   - If no test exists, create one following project conventions
   - Verify the new test passes

### 7b. Free-text findings (codex quick mode / gemini / ollama)

For each finding from Step 6b:

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
set_loop_phase ".claude/review-loop.loop.local.json" "verifying"
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

Stage only the files that were fixed in this pass. Do NOT use `git add -A` as it may sweep in unrelated working-tree changes:

```bash
git add <list of files modified during fix phase>
```

Track which files were edited during the fix phase (Step 7) and only stage those specific files.

**Only commit if there are staged changes.** Passes can legitimately have zero fixable findings (all skipped/invalid), so check before committing:

```bash
if ! git diff --cached --quiet; then
  git commit -m "fix: address $LLM_CHOICE review findings (pass $PASS)"
else
  echo "No changes to commit for this pass"
fi
```

Display summary for this pass:
- Findings reported by LLM
- Findings fixed
- Findings skipped (with reasons)
- Files changed
- Verification status

## 10. Loop Decision

### Multi-pass optimization for codex exec mode

Since `codex exec` returns ALL findings in a single pass (no artificial limit), additional passes are primarily useful for verification after fixes. When `LLM_CHOICE` is `codex` and `QUICK_MODE` is `false`:

- If pass 1 returned findings and they were all fixed, run ONE verification pass (pass 2) with the same prompt and a fresh diff
- If pass 2 is clean (zero findings) → stop immediately regardless of `MAX_PASSES`
- If pass 2 has findings, those are genuinely new issues introduced by fixes → continue normally

### Standard loop decision

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
