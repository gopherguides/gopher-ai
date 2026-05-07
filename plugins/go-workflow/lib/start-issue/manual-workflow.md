# Start-Issue — Manual Workflow (`--no-agents` fallback)

Loaded by `commands/start-issue.md` when `NO_AGENTS=true`. Single-session
flow for simple issues where subagent overhead is not justified.

## Bug Fix (Manual)

1. **Check for duplicates** (same as orchestrated Step 1)
2. **Create branch** (skip if worktree): `git checkout -b "fix/$ISSUE_NUM-<short-desc>"`
3. **Explore root cause**: grep for error text, read max 3 files, form hypothesis
4. **TDD Red — IRON LAW: No fix code before this test.** If you already wrote fix code, DELETE IT. Write a failing test. Run it. Verify it fails FOR THE RIGHT REASON. **Red flag: test passes immediately = wrong test.**
5. **TDD Green**: implement minimal fix. Run test. Verify it passes.
6. **Verify**: `go build ./...` + `go test ./...` + `golangci-lint run` (if installed)
7. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md`, follow Steps A-F
8. **Security review**: govulncheck, scan for secrets/injection/traversal
9. **Submit**: commit, push, create PR with template (per orchestrated Step 11)
10. **Watch CI**: `gh pr checks --watch`, fix failures

## Feature (Manual)

1. **Understand requirements**: read issue + comments, ask clarifying questions if ambiguous
2. **Explore codebase**: find similar implementations, patterns, integration points
3. **Design approach — HARD GATE**: propose 2-3 approaches, get user approval before coding
4. **Create branch** (skip if worktree): `git checkout -b "feat/$ISSUE_NUM-<short-desc>"`
5. **TDD Red — IRON LAW: No implementation code before these tests.** If you already wrote code, DELETE IT. Write comprehensive tests (happy path, edge cases, errors). Each test = ONE behavior. Run them. Verify they fail FOR THE RIGHT REASONS. **Red flag: test passes immediately = wrong test.**
6. **TDD Green**: implement minimal code. Run tests. Verify all pass.
7. **Verify**: `go build ./...` + `go test ./...` + `golangci-lint run` (if installed)
8. **Coverage**: Read `${CLAUDE_PLUGIN_ROOT}/skills/coverage/coverage-verification.md`, follow Steps A-F
9. **Security review**: govulncheck, scan for secrets/injection/traversal
10. **Submit**: commit, push, create PR with template (per orchestrated Step 11)
11. **Watch CI**: `gh pr checks --watch`, fix failures
