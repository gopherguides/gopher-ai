---
argument-hint: "[--llm codex|gemini|ollama] [--max-passes <n>] [--quick] [--tier flex|standard|priority] [scope hint]"
description: "Iterative LLM review loop: review, fix, verify, repeat until clean"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "Edit", "Write", "AskUserQuestion", "Agent"]
---

# Iterative LLM Review Loop

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "review-loop" "REVIEW_CLEAN" 25 "" '{"reviewing":"Resume the review-fix-verify cycle. Run the next review pass.","fixing":"Continue fixing: address remaining review findings, then verify.","verifying":"Continue verification: run build, test, and lint on fixes."}'; fi`

## 1. Parse Arguments

Parse `$ARGUMENTS` to extract:

- `--llm <value>`: `codex` (default), `gemini`, `ollama`
- `--max-passes <n>`: max review passes (default: 5)
- `--quick`: use `codex review` instead of `codex exec` (faster, limited to 2-3 findings per pass; codex only)
- `--tier <value>`: gemini service tier (`flex`/`standard`/`priority`; gemini only; default: unset)
- Remaining text: scope hint

Store as `LLM_CHOICE`, `MAX_PASSES`, `QUICK_MODE` (default `false`), `GEMINI_TIER`, `SCOPE_HINT`.

**Persist** to `.local/state/review-loop.loop.local.json` via `jq` (merge `args`, `pass: 0`, `quick_mode`, `gemini_tier`) so the stop-hook can restore on re-entry. See `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/state-persist.md` for the exact jq invocation; the same pattern repeats in Step 4c.

## 2. Prerequisite Check

Verify the selected LLM CLI is installed. **CRITICAL: Never silently fail or fall back** — always present the user with options via `AskUserQuestion`.

```bash
LLM_AVAILABLE=true
case "$LLM_CHOICE" in
  codex)  command -v codex >/dev/null 2>&1 && CODEX_CMD="codex" \
            || (npx -y codex --version >/dev/null 2>&1 && CODEX_CMD="npx -y codex") \
            || LLM_AVAILABLE=false ;;
  gemini) command -v gemini >/dev/null 2>&1 || LLM_AVAILABLE=false ;;
  ollama) command -v ollama >/dev/null 2>&1 || LLM_AVAILABLE=false ;;
esac
```

If `LLM_AVAILABLE=false` → ask the user via `AskUserQuestion` with options **Retry** / **Debug / Install instructions** / **Abort**. On **Abort**, run `"${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "review-loop"` and output `<done>REVIEW_CLEAN</done>`.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/prerequisites.md` for the diagnostic-output block and the per-LLM install instructions.

## 3. Re-entry Check

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
STATE_FILE=".local/state/review-loop.loop.local.json"
[ -f "$STATE_FILE" ] && read_loop_state "$STATE_FILE"
```

If `PHASE` is set (non-empty), this is a stop-hook re-entry. Restore from state file (re-parse `args` for `LLM_CHOICE`/`MAX_PASSES`/`QUICK_MODE`/`SCOPE_HINT`; read `pass`, `scope`, `base_branch`, `model`, `file_paths`, `quick_mode`, `gemini_tier` via `jq -r '.<field> // empty'`) then jump:

- `reviewing` → Step 5
- `fixing` → Step 7
- `verifying` → Step 8

If `PHASE` is empty/unset, this is a fresh start. Continue to Step 4.

## 4. Detect Review Scope

### 4a. Silent PR Auto-Detection

Before asking any questions, silently detect PR context using three strategies (current branch / HEAD-search open / HEAD-search any-state). The exact bash for these strategies plus base-branch fallback is the same as in `review-deep` Step 1; if needed, see `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/scope-detect.md`.

### 4b. Ask User for Review Scope

Use a **single `AskUserQuestion` call** with two questions.

**Q1 — "What do you want to review?":** options `Changes vs branch` (Recommended; against base branch, default `main`) / `Uncommitted changes` (staged, unstaged, untracked) / `Specific files` (paths).

**Q2 — "Which model?":** show options based on `LLM_CHOICE`:

- **codex:** `gpt-5.5` (Recommended), `gpt-5.5-pro`, `gpt-5.3-codex`, `gpt-5.1-codex-mini`
- **gemini:** `gemini-2.5-pro` (Recommended), `gemini-2.5-flash`
- **ollama:** `codellama` (Recommended), `llama3`, `deepseek-coder`, Custom

### 4c. Auto-Detect Base Branch & Conditional Follow-Up

For "Changes vs branch" / "Specific files": reuse `PR_JSON` from 4a, fall back to `origin/HEAD`/remote default/`main`. Display the detected branch.

Remaining follow-ups (only ask if needed): "Specific files" → ask paths; "Custom" model → ask model name.

Persist `scope`, `base_branch`, `model`, `file_paths` to the state file via `jq` (same pattern as Step 1). See `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/state-persist.md` for the exact invocation.

## 5. Review Phase

```bash
source "${CLAUDE_PLUGIN_ROOT}/lib/loop-state.sh"
set_loop_phase ".local/state/review-loop.loop.local.json" "reviewing"
# Increment pass counter in state file; read updated value into PASS
```

**Generate diff per `REVIEW_SCOPE`:**

- Changes vs branch: `git diff ${BASE_BRANCH}...HEAD`
- Uncommitted: `git diff HEAD` (don't add `--cached`, it duplicates staged hunks); include untracked file content via `git ls-files --others --exclude-standard`
- Specific files: `git diff ${BASE_BRANCH}...HEAD -- <file_paths>`

**Run LLM review** — four paths (codex exhaustive `exec --output-schema`, codex quick `review`, gemini, ollama). Each includes diff-size warning, adaptive timeout for codex, and `AskUserQuestion`-based error handling — never silently fail.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/review-phase.md` for prompt-template assembly, `gtimeout`/`timeout` detection, 3000-line large-diff warning, exit-code 124 timeout handling, "Drop --output-schema" / "Use codex review --base" fallback options, gemini/ollama heredocs, and the `GEMINI_TIER` warning text.

## 6. Parse Findings

- **Structured JSON** (codex exec, `QUICK_MODE=false`, `CODEX_EXEC_FALLBACK!=true`): validate JSON, filter `confidence_score < 0.3` FIRST, check for clean AFTER filtering, sort by priority then confidence, display table, de-duplicate across passes via state file
- **Free-text** (codex quick / gemini / ollama): exact-match `NO_ISSUES_FOUND` clean signal, parse findings from output

**Always filter bot noise** — silently discard findings containing usage-limit / quota messages.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/parse-findings.md` for the jq filter chain, de-duplication keying, per-pass `findings_pass_<N>` state-file write, and the formatted-table layout.

## 7. Fix Phase

```bash
set_loop_phase ".local/state/review-loop.loop.local.json" "fixing"
```

For each finding (priority P0 → P3): read file at cited line range, evaluate validity, auto-skip `priority == 3` AND `confidence < 0.5`, make minimal fix or record skip reason, generate a test for testable fixes.

**Parallel dispatch** when 3+ findings target different files: group by file (and shared `_test.go` per package), dispatch one Agent subagent per group with `run_in_background: true`, then aggregate. Fall back to sequential when <3 findings, free-text findings, or all findings target the same file.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/fix-phase.md` for the structured/free-text iteration bash, the dispatch agent prompt, and per-language test-generation conventions.

## 8. Verify Phase

```bash
set_loop_phase ".local/state/review-loop.loop.local.json" "verifying"
```

Auto-detect project type (`go.mod`, `package.json`, `Cargo.toml`, `pyproject.toml`/`setup.py`) and run the matching build + test + (optional) lint commands. If no project type detected, ask the user for the verify command.

If any verification fails: analyze, fix, re-run, repeat until all pass.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/verify-and-commit.md` for the per-language command set and the Step 9 commit logic (stage modified files only — never `git add -A`; commit only when there are staged changes; per-pass summary line).

## 9. Commit Fixes

See `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/verify-and-commit.md`. Commit message format: `fix: address $LLM_CHOICE review findings (pass $PASS)`. After commit, display the per-pass summary: findings reported / fixed / skipped (with reasons), files changed, verification status.

## 10. Loop Decision

**Codex `exec` optimization:** exhaustive mode returns ALL findings in pass 1, so additional passes are mainly for verification. After pass 1's fixes, run ONE verification pass — if zero findings, stop immediately regardless of `MAX_PASSES`. New issues from fixes → continue normally.

**Standard:** if `PASS >= MAX_PASSES`, ask "Max passes reached. Continue or stop?" via `AskUserQuestion`. Stop → output `<done>REVIEW_CLEAN</done>`. Continue → reset `MAX_PASSES = MAX_PASSES + current value` and go to Step 5. Otherwise → go to Step 5.

## Completion

Output a summary then `<done>REVIEW_CLEAN</done>`:

```
## Review Loop Complete

- **LLM:** <llm> (<model>)
- **Total passes:** <n>
- **Findings addressed:** <n>
- **Findings skipped:** <n> (with reasons listed)
- **Files changed:** <list>
- **All verifications passed:** yes/no
```

## Important Notes

- **Bot message filtering:** silently discard any content about external service usage limits or quota messages.
- **De-duplication across passes:** skip any (file, line, issue) tuple that appeared in a previous pass — it was already addressed or intentionally skipped.
- **Cancel:** `/cancel-loop review-loop` cleanly exits.

## Further Reading

All sibling files live under `${CLAUDE_PLUGIN_ROOT}/lib/review-loop/`:

- `prerequisites.md` — Step 2 diagnostics + install instructions
- `scope-detect.md` — Step 4a's three PR-detection strategies + base-branch fallback
- `state-persist.md` — the jq merge pattern shared by Steps 1 and 4c
- `review-phase.md` — Step 5b's LLM execution paths (codex exhaustive/quick, gemini, ollama), prompt assembly, timeout + error handling
- `parse-findings.md` — Step 6's structured + free-text parsing, de-duplication
- `fix-phase.md` — Step 7's iteration, parallel-dispatch agent prompt, test generation
- `verify-and-commit.md` — Step 8 per-language commands + Step 9 staged-commit logic
