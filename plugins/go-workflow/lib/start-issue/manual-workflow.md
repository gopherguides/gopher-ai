# Start-Issue — Manual Workflow (`--no-agents` fallback)

Loaded by `skills/start-issue/SKILL.md` when `NO_AGENTS=true`. Single-session
flow for simple issues where subagent overhead is not justified.

## Bug Fix (Manual)

1. **Check for duplicates** (same as orchestrated Step 1, including its
   standalone-or-embedded structured result contract)
2. **Create branch** (skip if worktree): `git -C "$WORKTREE_PATH" checkout -b "fix/$ISSUE_NUM-<short-desc>"`
3. **Explore root cause**: grep for error text, read max 3 files, form hypothesis
4. **TDD Red — IRON LAW: No fix code before this test.** If you already wrote fix code, DELETE IT. Write a failing test. Run it. Verify it fails FOR THE RIGHT REASON. **Red flag: test passes immediately = wrong test.**
5. **TDD Green**: implement minimal fix. Run test. Verify it passes.
6. **Verify**: `go -C "$WORKTREE_PATH" build ./...` + `go -C "$WORKTREE_PATH" test ./...` + `(cd "$WORKTREE_PATH" && golangci-lint run)` (if installed)
7. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/lib/coverage/coverage-verification.md`, follow Steps A-F
8. **Security review**: `(cd "$WORKTREE_PATH" && govulncheck ./...)`, scan for secrets/injection/traversal
9. **Submit**: commit with `git -C "$WORKTREE_PATH"`, push that explicit head, and create the PR with `gh pr create --repo "$REPO_SLUG" --head "$(git -C "$WORKTREE_PATH" branch --show-current)"` using the template from orchestrated Step 11
10. **Watch CI**: `gh pr checks "$PR_NUM" --repo "$REPO_SLUG" --watch`, fix failures

## Feature (Manual)

1. **Understand requirements**: read the issue and comments. Resolve technical ambiguity from repository evidence. If materially different product behavior or acceptance criteria remain unspecified, follow the shared missing-intent gate and stop before implementation.
2. **Explore codebase**: find similar implementations, patterns, integration points
3. **Design approach**: propose 2-3 approaches, then choose from requirements, repository patterns, reversibility, and risk. State `Decision`, `Evidence`, and `Rationale`. Use the missing-intent gate only when the approaches imply materially different unspecified product behavior.
4. **Create branch** (skip if worktree): `git -C "$WORKTREE_PATH" checkout -b "feat/$ISSUE_NUM-<short-desc>"`
5. **TDD Red — IRON LAW: No implementation code before these tests.** If you already wrote code, DELETE IT. Write comprehensive tests (happy path, edge cases, errors). Each test = ONE behavior. Run them. Verify they fail FOR THE RIGHT REASONS. **Red flag: test passes immediately = wrong test.**
6. **TDD Green**: implement minimal code. Run tests. Verify all pass.
7. **Verify**: `go -C "$WORKTREE_PATH" build ./...` + `go -C "$WORKTREE_PATH" test ./...` + `(cd "$WORKTREE_PATH" && golangci-lint run)` (if installed)
8. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/lib/coverage/coverage-verification.md`, follow Steps A-F
9. **Security review**: `(cd "$WORKTREE_PATH" && govulncheck ./...)`, scan for secrets/injection/traversal
10. **Submit**: commit with `git -C "$WORKTREE_PATH"`, push that explicit head, and create the PR with `gh pr create --repo "$REPO_SLUG" --head "$(git -C "$WORKTREE_PATH" branch --show-current)"` using the template from orchestrated Step 11
11. **Watch CI**: `gh pr checks "$PR_NUM" --repo "$REPO_SLUG" --watch`, fix failures
