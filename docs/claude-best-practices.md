# Claude Code Best Practices Reference

> **This document is designed for LLM consumption.** It contains battle-tested CLAUDE.md configuration rules with full context, reasoning, and examples so that an AI coding assistant can read it, compare it against a developer's current configuration, and guide them through adoption.

---

## How to Use This Document

**You are an AI coding assistant helping a developer configure their `~/.claude/CLAUDE.md` (or equivalent global config).** Follow this workflow:

1. Read this entire document to understand all available best practices
2. Read the developer's current `~/.claude/CLAUDE.md` file
3. Compare section-by-section: identify which practices they already have, which are missing, and which partially overlap
4. Present each missing practice with the "Why This Matters" explanation
5. Let the developer choose which to adopt — do not force all sections
6. For adopted sections, insert the snippet verbatim into their config file, merging with any existing related sections rather than duplicating

---

## 1. Critical Safety Rules

### Why This Matters

Without these rules, AI assistants will execute destructive commands without warning. Real failure scenarios:
- `rm -rf` deleting an entire project directory when the assistant misunderstood a cleanup request
- `git reset --hard` discarding hours of uncommitted work because the assistant thought it was "cleaning up"
- A bulk find-and-replace across 200 files that introduced bugs because the assistant didn't ask first
- Overwriting a file the developer was actively editing because the assistant didn't read it first

### Snippet

```markdown
## Critical Safety Rules

- ALWAYS confirm destructive operations (rm, git reset --hard, etc.) before execution
- NEVER overwrite files without reading them first unless explicitly requested
- Ask for confirmation before making bulk changes across multiple files
- Never do a git reset hard with uncommitted code without getting a confirmation and issue a warning first stating code is about to be lost
```

### Customization Notes

These rules are universal. No customization needed. They should be adopted verbatim by every developer.

---

## 2. Code Quality Standards

### Why This Matters

Without these rules, AI assistants tend to:
- Create new files instead of editing existing ones, causing file bloat and duplicate implementations
- Add unsolicited docstrings, comments, and type annotations to code they didn't change, creating noisy diffs
- Ignore project conventions (import ordering, naming patterns, file organization) and introduce inconsistencies
- Miss that a utility function already exists and create a duplicate

Example failure: The assistant is asked to add a validation function. Without these rules, it creates `utils/validation.go` instead of adding the function to the existing `internal/validate/validate.go` where the team keeps all validation logic. Now there are two validation locations and the team is confused about which to use.

### Snippet

```markdown
## Code Quality Standards

- Always check for existing code patterns and follow project conventions before writing new code
- Prefer editing existing files over creating new ones unless specifically requested
- NEVER add comments to code unless explicitly asked
- Follow the project's import organization and naming conventions
- Check for project-specific CLAUDE.md files and follow those patterns first
```

### Customization Notes

The "NEVER add comments" rule is opinionated. Some teams prefer the assistant to add comments. Developers who want comments can change this to: "Add concise comments only for non-obvious logic." The other rules are universal.

---

## 3. Git Worktrees

### Why This Matters

Git worktrees allow developers to work on multiple branches simultaneously without stashing or switching. AI assistants that don't understand worktrees will:
- Remove a worktree to checkout the branch in the main repo, destroying the developer's in-progress work in that worktree
- Try to `git checkout` a branch that's already checked out in a worktree (git refuses this), then try to force it
- Suggest `git stash` workflows when the developer is already using worktrees

Example failure: Developer has `../myproject-issue-42/` with uncommitted changes. The assistant runs `git worktree remove ../myproject-issue-42` to "clean up" before checking out the branch, destroying all uncommitted work.

### Snippet

```markdown
## Git Worktrees

- **NEVER remove worktrees** to checkout a branch in the main repo. Always work directly from the worktree directory.
- When worktrees exist, `cd` into the worktree path to do work — do NOT try to checkout the branch elsewhere.
- Worktrees are the user's working state. Removing them can destroy uncommitted work.
```

### Customization Notes

Only relevant for developers who use git worktrees. If the developer doesn't use worktrees, this section can be skipped. If they do use worktrees, adopt verbatim.

---

## 4. Git & Version Control

### Why This Matters

Without explicit branch protection rules, AI assistants will happily commit directly to `main`, create inconsistent commit messages, and fabricate PR descriptions from their session context (which may be stale) instead of checking the actual git state.

Example failures:
- Assistant commits a "quick fix" directly to `main`, bypassing the team's PR review process
- Commit messages alternate between styles: `"Add login feature"`, `"feat: add login"`, `"added login stuff"` — making git history unreadable
- Assistant generates a PR description from what it remembers doing, but it forgot about a revert mid-session. The PR description is wrong.

### Snippet

```markdown
## Git & Version Control

- **NEVER commit directly to main/master branch** - always create a feature branch first unless the user EXPLICITLY states to make changes on main
- NEVER commit changes unless explicitly requested
- Always check git status before making changes to understand current state
- **Git Commits**: Use conventional format: `<type>(<scope>): <subject>` where type = feat|fix|docs|style|refactor|test|chore|perf. Subject: 50 chars max, imperative mood ("add" not "added"), no period. For small changes: one-line commit only. For complex changes: add body explaining what/why (72-char lines) and reference issues. Keep commits atomic (one logical change) and self-explanatory. Split into multiple commits if addressing different concerns.
- Check for merge conflicts before suggesting branch operations
- Use `gh` CLI when asked to look at GitHub issues
- Always do a thorough check from the branch you are on to the branch you started from to create commit and PR messages, don't use the session context you are in as you'll get false data
```

### Customization Notes

- The conventional commit format (`type(scope): subject`) is the most common standard but some teams use different formats. Check the developer's existing git log (`git log --oneline -20`) and match their convention.
- The "NEVER commit unless explicitly requested" rule prevents surprise commits. Some developers prefer the assistant to auto-commit after completing work. Adjust to preference.
- The last rule about checking actual git state vs session context is critical and should not be removed — AI assistants routinely hallucinate what they did vs what actually happened.

---

## 5. CI Watch After Push

### Why This Matters

After pushing code to a PR, many developers (and AI assistants) consider the task done. But CI often catches issues the local environment missed: lint rules, test failures in other OS/Go versions, security scanning. Without this rule, the assistant marks work "complete" while CI is red.

A subtle problem: GitHub Actions can take 10-30 seconds to register checks after a push. Running `gh pr checks` immediately often returns "no checks reported," which naive assistants interpret as "no CI configured" and move on. The retry logic below handles this race condition.

### Snippet

```markdown
### CI Watch After Push

After pushing to a PR, always watch CI and fix failures:

1. Run: `gh pr checks --watch` (or `gh pr checks <PR_NUMBER> --watch`)
2. **If "no checks reported"**: CI takes time to register after a push. **Wait 10 seconds and retry, up to 3 times**, before concluding there are truly no checks. Example retry loop:
   ```bash
   for i in 1 2 3; do sleep 10 && gh pr checks <PR_NUMBER> --watch && break; done
   ```
   If still no checks after retries, verify the repo actually has CI workflow files before concluding there are none:
   ```bash
   find .github/workflows -maxdepth 1 -name '*.yml' -o -name '*.yaml' 2>/dev/null | head -1 | grep -q . || echo "No workflow files found"
   ```
   Only conclude there are no CI checks if no `.yml`/`.yaml` workflow files exist. If workflow files exist, the checks are still propagating — wait longer and retry.
3. If checks fail:
   - Get failure details: `gh pr checks --json name,state,description`
   - Analyze and fix the failing check (test, lint, build)
   - Commit and push the fix
   - Return to step 1
4. Only mark work complete when all CI checks pass

**Do not consider a PR ready or task complete until CI is green.**
```

### Customization Notes

- Requires `gh` CLI installed and authenticated. If the developer doesn't use `gh`, they'll need to install it first (`brew install gh` / `apt install gh`).
- The retry logic (3 attempts, 10 seconds apart) works for most GitHub Actions setups. Larger repos or self-hosted runners may need longer delays.
- Some teams have flaky tests that fail intermittently. If so, the developer may want to add: "If a check fails and appears to be a known flaky test (not related to your changes), note it in the PR but do not block on it."

---

## 6. Pull Request Creation

### Why This Matters

`gh pr create` does NOT auto-populate from `.github/PULL_REQUEST_TEMPLATE.md` like the GitHub web UI does. Without this rule, AI assistants generate freeform PR descriptions that ignore the team's template, missing required sections like test plans, security checklists, or deployment notes.

Example failure: The team's PR template requires a "## Database Migrations" section. The assistant creates a PR that adds a migration but the PR body doesn't mention it. The reviewer doesn't notice, the migration runs in production without review.

### Snippet

```markdown
## Pull Request Creation

When creating any pull request in any repository:
1. Check for a PR template at `.github/pull_request_template.md` or `.github/PULL_REQUEST_TEMPLATE.md` (also check `docs/` and repo root)
2. If found, read the template and follow its exact section structure for the PR body — fill in every section, do not omit or skip any
3. If not found, use this default format: `## Summary` (bullet points), issue reference (`Fixes #N`), `## Test Plan`
4. Always pass the body via heredoc to `gh pr create` to preserve formatting
```

### Customization Notes

Universal. The template detection order follows GitHub's documented precedence. The default format (Summary + Test Plan) is a reasonable minimum. Teams with more specific needs should create a `.github/pull_request_template.md` in their repos.

---

## 7. Environment & Dependencies

### Why This Matters

AI assistants frequently assume libraries, tools, or runtimes are available without checking. This leads to suggestions that fail immediately ("run `pytest`" in a project that uses `go test`, or `npm install` in a project with no `package.json`).

Example failure: Assistant suggests `make build` but the project uses a `Justfile`, not a `Makefile`. Or it suggests `golangci-lint run` but the project uses `revive` as its linter.

### Snippet

```markdown
## Environment & Dependencies

- Check for project-specific package.json, go.mod, or similar dependency files before assuming library availability
- Look for Makefile or build scripts to understand the project's build process
- Respect any CI/CD configurations when making changes
- Check .github/workflows to see what linters will run in CI
```

### Customization Notes

Universal. Developers working in monorepos may want to add: "Check the nearest package.json/go.mod relative to the current working directory, not just the repo root."

---

## 8. Project Discovery

### Why This Matters

Many projects have their own `CLAUDE.md` with project-specific rules (import ordering, test patterns, architectural constraints). Without this rule, the assistant ignores these files and follows its defaults, creating code that doesn't match the project's conventions.

Example failure: The project's CLAUDE.md says "always use `sqlc` for database queries, never write raw SQL." The assistant writes raw SQL because it didn't read the project instructions.

### Snippet

```markdown
## Project Discovery

- Read project-specific CLAUDE.md files and prioritize those instructions
- Search existing code for patterns when unsure about project conventions
- Check README files for setup and build instructions
```

### Customization Notes

Universal. For Cursor users, the equivalent files are `.cursorrules` or `.cursor/rules/*.mdc`. For Codex, it's `AGENTS.md` or `codex.md`. The principle is the same: always check for project-level instructions first.

---

## 9. Communication Style

### Why This Matters

Without these rules, AI assistants tend to be verbose, provide unsolicited explanations, reference code without file paths (making it hard to navigate), and make assumptions about ambiguous requests instead of asking.

Example failure: Developer asks "what's the bug in the login flow?" The assistant guesses at a bug based on code patterns instead of asking "which login flow — the OAuth flow in `auth/oauth.go` or the session flow in `auth/session.go`?"

### Snippet

```markdown
## Communication Style

- Be concise in responses unless detailed explanation is requested
- Provide file paths with line numbers when referencing code: `file.go:123`
- Focus on the specific task requested, avoid unnecessary explanations
- When unsure, ask clarifying questions rather than making assumptions
```

### Customization Notes

The `file.go:123` format works for most editors and terminals (clickable links). Some developers may prefer different formats. The "be concise" rule can be relaxed for developers who prefer verbose explanations — change to "Provide detailed explanations by default."

---

## 10. Planning & Issue Creation

### Why This Matters

AI assistants default to including time estimates when creating plans or GitHub issues ("This should take 2-3 days"). These estimates are almost always wrong in AI-assisted development because:
- The AI doesn't know the developer's skill level, interruptions, or other commitments
- AI-assisted implementation speed varies wildly based on code complexity
- Estimates create false expectations and unnecessary pressure

Example failure: The assistant creates a GitHub issue with "Estimated: 1-2 weeks" for a feature. Management sees the estimate and schedules a demo. The feature takes 3 weeks due to unforeseen complexity. Now there's a scheduling conflict that didn't need to exist.

### Snippet

```markdown
## Planning & Issue Creation

- **NEVER include timeline estimates** when creating plans, GitHub issues, or task breakdowns
- **NEVER use phased timelines** like "1-2 weeks for X", "Phase 1: Weeks 1-2", "3-4 weeks for Y feature"
- With AI-assisted programming, traditional time estimates are neither helpful nor accurate
- Instead, focus on **actionable steps** and **what** needs to be done, not **when**
- Break work into concrete, executable tasks without temporal constraints
- Use iterative planning: identify next steps, complete them, reassess
- Let the user decide scheduling and priorities - provide implementation steps only
- When breaking down complex work, use logical groupings (by feature, component, dependency) not time phases
```

### Customization Notes

This is opinionated. Some teams require time estimates in their issue templates or project management tools. If so, the developer can soften to: "Only include time estimates when explicitly asked, and caveat them as rough approximations." The core principle — group by logical concern, not time phases — is universally applicable.

---

## 11. Chrome DevTools MCP Screenshots

### Why This Matters

The Chrome DevTools MCP server allows AI assistants to take screenshots of web pages for visual debugging. Without these rules, assistants take full-page screenshots of long pages at high DPR (device pixel ratio), producing images that exceed size limits and fail silently or return corrupted output.

Example failure: Assistant takes a `fullPage: true` screenshot of a page that's 5000px tall at DPR 3. The resulting image is 15000px tall, exceeds the 8000px dimension limit, and the tool returns an error or a blank image. The assistant retries repeatedly, wasting time.

### Snippet

```markdown
### Chrome DevTools MCP Screenshots

- NEVER use `fullPage: true` without first checking page length
- Prefer viewport screenshots over full-page screenshots - they're usually sufficient
- Reduce DPR to 1 before taking full-page screenshots: use `emulate` tool with `deviceScaleFactor: 1`
- Check dimensions first: Full page height x DPR x width x DPR must stay under 8000px on any dimension
- For long pages: Take multiple viewport screenshots instead of one full-page screenshot
- Mobile emulation warning: A 375px wide viewport with DPR 2 becomes 750px wide; a page 4000px tall becomes 8000px tall and will fail
- Safe approach: Always use viewport screenshot first. Only use fullPage if specifically needed AND after reducing DPR to 1
```

### Customization Notes

Only relevant for developers using the `chrome-devtools-mcp` server. If the developer doesn't use browser automation in their Claude Code sessions, skip this section. The 8000px limit is a current constraint of the tool and may change in future versions.

---

## Section Adoption Checklist

When comparing against the developer's existing config, use this quick reference:

| # | Section | Universal? | Skip If... |
|---|---------|-----------|------------|
| 1 | Critical Safety Rules | Yes | Never skip |
| 2 | Code Quality Standards | Yes | Never skip |
| 3 | Git Worktrees | Conditional | Developer doesn't use worktrees |
| 4 | Git & Version Control | Yes | Never skip |
| 5 | CI Watch After Push | Yes | No CI/CD, no `gh` CLI |
| 6 | Pull Request Creation | Yes | Never creates PRs via CLI |
| 7 | Environment & Dependencies | Yes | Never skip |
| 8 | Project Discovery | Yes | Never skip |
| 9 | Communication Style | Yes | Never skip |
| 10 | Planning & Issue Creation | Yes | Team requires time estimates |
| 11 | Chrome DevTools MCP | Conditional | No browser MCP usage |
