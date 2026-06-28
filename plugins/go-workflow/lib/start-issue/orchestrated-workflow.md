# Start-Issue — Subagent-Orchestrated Workflow

Loaded by `skills/start-issue/SKILL.md` when `NO_AGENTS=false` (the default).
The orchestrator (the trunk's session) retains all control flow, verification
gates, and external interactions; subagents handle exploration,
implementation, and review.

## Subagent Model Policy

Each prompt under `${CLAUDE_PLUGIN_ROOT}/agents/` declares its default `model`
frontmatter. Do not pass a per-dispatch model in this workflow unless the user
explicitly requests a one-off override; doing so would mask the prompt's model
policy.

When dispatching, always set `subagent_type` to the prompt file's frontmatter
`name` so Claude Code loads that custom subagent definition and applies its
model policy.

Defaults:

| Agent prompt | Model policy | Purpose |
|--------------|--------------|---------|
| `explore-prompt.md` | `haiku` | Read-only codebase exploration |
| `implementer-prompt.md` | `inherit` | TDD implementation keeps the parent session's model |
| `spec-review-prompt.md` | `sonnet` | Mechanical requirements checklist |
| `quality-review-prompt.md` | `sonnet` | Go idiom, complexity, security, and test review |

To override all subagent models for a run, set `CLAUDE_CODE_SUBAGENT_MODEL`
before invoking `$start-issue` or `$complete-issue`. To avoid subagents
entirely, pass `--no-agents`.

## Step 1: Check for Duplicates (Bug Fix Only)

If issue is a **bug**:

```bash
gh issue list --state all --limit 50 --search "<key terms from title/body>"
```

If potential duplicates found, present them and ask the user via
`AskUserQuestion` how to proceed (Continue / Skip / Link).

## Step 2: Create Branch (skip if worktree was created)

REQUIRED unless using a worktree. Never commit to main/master.

For bugs: `git checkout -b "fix/$ISSUE_NUM-<short-desc>"`
For features: `git checkout -b "feat/$ISSUE_NUM-<short-desc>"`

Verify: `git branch --show-current`

## Step 3: Explore Phase

Read `${CLAUDE_PLUGIN_ROOT}/agents/explore-prompt.md` and fill in:

- `{ISSUE_TITLE}` — from issue context
- `{ISSUE_BODY}` — from issue context (body + comments)
- `{ISSUE_TYPE}` — "bug" or "feature"
- `{WORKTREE_PATH}` — absolute path to working directory
- `{REPO_CONVENTIONS}` — from CLAUDE.md or AGENTS.md if present

Dispatch:

```
Agent(prompt=<filled template>, subagent_type=explore-prompt)
```

Store the results: `RELEVANT_FILES`, `PATTERNS`, `ROOT_CAUSE` (bugs) or `INTEGRATION_POINTS` (features), `PROPOSED_CHANGES`, `TASK_DECOMPOSITION`.

## Step 4: Design Approach (Features Only)

Present the plan before implementing. Plan approval is the gate — once the user accepts the plan, you have approval for everything in it (including data migrations, schema changes, and new packages). Do not stop again to re-confirm individual items that were already in the approved plan.

Using the Explore results, propose 2-3 approaches with concrete trade-offs:

- What it changes (files, types, APIs, schema/migrations)
- Trade-offs (complexity vs simplicity, performance vs maintainability)
- Your recommendation and why

**Surface migrations and schema changes explicitly in the plan** so the user can see them and approve in one shot. Do not treat migrations as a separate hard gate.

**For trivial features** (single function, obvious implementation): state your plan and proceed unless the user objects.

**For non-trivial features** (new package, API changes, data model changes): present approaches and recommend one. Use your judgment on whether to wait for an explicit reply — if the change is risky, irreversible, or you're genuinely uncertain which approach the user wants, ask. Otherwise, state the recommended plan and proceed unless the user objects.

## Step 5: Task Decomposition

Using the Explore results and approved approach:

**For bugs:** Typically 1 task — fix the root cause identified in the Explore phase.

**For features:** Decompose into N tasks where each task:

- Has a clear description of what to implement
- Lists `TARGET_FILES` (files to create/modify) — must be disjoint across tasks for parallel dispatch
- Lists `TEST_FILES`
- Lists `CONTEXT_FILES` (read-only reference files)
- Notes dependencies on other tasks (empty = independent)

**Parallel dispatch decision:** if ALL tasks have disjoint `TARGET_FILES` AND disjoint `TEST_FILES` (including shared test helpers in the same package) and no dependencies, they can run in parallel. Otherwise, sequential. Two tasks in the same Go package almost always share a `_test.go` file — default to sequential for same-package tasks.

## Step 6: Implementation Phase

For each task, read `${CLAUDE_PLUGIN_ROOT}/agents/implementer-prompt.md` and fill in:

- `{TASK_DESCRIPTION}` — from task decomposition
- `{TARGET_FILES}` — files this agent may create/modify
- `{TEST_FILES}` — test file(s) for this task
- `{WORKTREE_PATH}` — absolute path to working directory
- `{PATTERNS}` — from Explore results
- `{CONTEXT_FILES}` — read-only reference files
- `{ISSUE_TYPE}` — "bug" or "feature"

**Dispatch:**

- **Parallel** (independent tasks with disjoint files):
  ```
  For each task: Agent(prompt=<filled>, subagent_type=implementer-prompt, run_in_background=true)
  Wait for all to complete. Collect results.
  ```
- **Sequential** (dependent tasks or overlapping files):
  ```
  For each task in order: Agent(prompt=<filled>, subagent_type=implementer-prompt)
  ```

**Handle subagent status:**

| Status | Action |
|--------|--------|
| DONE | Continue to next task or review phase |
| DONE_WITH_CONCERNS | Evaluate concerns — fix correctness issues before proceeding |
| NEEDS_CONTEXT | Supply the requested information, re-dispatch the implementer |
| BLOCKED | Present blockers to user via `AskUserQuestion`, get guidance |

## Step 7: Spec Compliance Review

After ALL implementation tasks complete:

```bash
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main")
git fetch origin "$DEFAULT_BRANCH" 2>/dev/null || true
git diff "origin/${DEFAULT_BRANCH}...HEAD"
```

Read `${CLAUDE_PLUGIN_ROOT}/agents/spec-review-prompt.md` and fill in:

- `{ISSUE_TITLE}`, `{ISSUE_BODY}`, `{ACCEPTANCE_CRITERIA}` — from issue context
- `{WORKTREE_PATH}` — working directory
- `{CHANGED_FILES}` — list of all files changed
- `{DIFF}` — the full diff

Dispatch: `Agent(prompt=<filled>, subagent_type=spec-review-prompt)`

**If VERDICT = FAIL:** address missing requirements by re-dispatching implementer subagent(s) for the gaps. Re-run spec review (max 2 retry cycles).

**If VERDICT = PASS:** proceed to Step 8.

## Step 8: Code Quality Review

Read `${CLAUDE_PLUGIN_ROOT}/agents/quality-review-prompt.md` and fill in `{WORKTREE_PATH}`, `{CHANGED_FILES}`, `{DIFF}`, `{PATTERNS}` (from Explore), `{REPO_CONVENTIONS}` (from CLAUDE.md/AGENTS.md).

Dispatch: `Agent(prompt=<filled>, subagent_type=quality-review-prompt)`

**If HAS_FINDINGS:**

- Priority 0-1 (critical/high): fix these directly, then re-run quality review (max 1 retry)
- Priority 2-3 (medium/low): note in PR description but do not block

**If CLEAN:** proceed to Step 9.

## Step 9: Verify

Run the full verification checklist. **All must pass before proceeding:**

- **Build**: `go build ./...`
- **All tests**: `go test ./...`
- **Lint**: `golangci-lint run` (if available)
- **Build logs**: if a dev server is running, check its log output for errors

If any step fails, fix the issue and re-run until all green.

## Step 9.5: Coverage Verification

Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md` and follow Steps A through F with:

| Variable | Value |
|----------|-------|
| `BASE_BRANCH` | `origin/${DEFAULT_BRANCH}` (compute if not already set: `git remote show origin 2>/dev/null \| grep 'HEAD branch' \| sed 's/.*: //' \|\| echo "main"`) |
| `STATE_FILE` | Absolute path to `.local/state/start-issue-$ISSUE_NUM.loop.local.json` (in the original repo, not the worktree) |
| `SKIP_COVERAGE` | from parsed flags (default: `false`) |
| `COVERAGE_THRESHOLD` | from parsed flags (default: `60`) |

After coverage verification completes (or is skipped), continue to Step 10.

## Step 10: Security Review

Before submitting, scan for security issues in changed files:

- **Dependency vulnerabilities**: `govulncheck ./...` (if available)
- **Scan changed files** for common Go security issues:
  - Hardcoded secrets or credentials
  - SQL injection (string concatenation in queries instead of parameterized)
  - Path traversal (`filepath.Join` with user input without `filepath.Clean`)
  - Unsafe `exec.Command` with unsanitized user input
  - Missing error checks on security-critical operations (crypto, auth, file permissions)
- **If changes touch auth, crypto, or data handling code**, suggest running `/codex review` with a security focus

## Step 11: Submit

1. Stage and commit with a conventional commit message referencing the issue
2. Push the branch: `git push -u origin <branch>`
3. **Check for PR template** — look in these locations (in order):
   - `.github/pull_request_template.md`
   - `.github/PULL_REQUEST_TEMPLATE.md`
   - `.github/PULL_REQUEST_TEMPLATE/` (directory with multiple templates — list and ask user which to use)
   - `docs/pull_request_template.md`
   - `docs/PULL_REQUEST_TEMPLATE/` (directory with multiple templates)
   - `pull_request_template.md` (repo root)
   - `PULL_REQUEST_TEMPLATE/` (repo root directory with multiple templates)
4. **If template found**: read the template and use its exact section structure for the PR body. Fill in every section — do not omit or skip sections. Always include `Fixes #<issue-number>` or `Closes #<issue-number>` even if the template doesn't have a dedicated section for it.
5. **If no template found**, use this default:
   ```
   ## Summary
   <1-3 bullet points describing what changed and why>

   Fixes #<issue-number>

   ## Test Plan
   <How the changes were tested>
   ```
6. Create the PR with heredoc formatting:
   ```bash
   gh pr create --title "<type>(<scope>): <subject>" --body "`cat <<'EOF'
   <filled-in template or default body>
   EOF
   `"
   ```

## Step 12: Watch CI

After creating the PR, watch CI and fix any failures:

1. `gh pr checks --watch`
2. **If "no checks reported"**: wait 10 seconds and retry, up to 3 times:
   ```bash
   for i in 1 2 3; do sleep 10 && gh pr checks --watch && break; done
   ```
   If still no checks after retries, verify CI workflow files exist.
3. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check
   - Commit and push the fix
   - Return to step 1
4. Continue only when all checks pass.
