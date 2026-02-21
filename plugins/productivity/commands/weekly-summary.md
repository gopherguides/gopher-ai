---
argument-hint: "[weeks-back]"
description: "Generate weekly work summary from git activity"
model: haiku
allowed-tools: ["Bash(git:*)", "Bash(date:*)", "Bash(find:*)", "Read", "Glob", "Grep"]
---

## Context

- Current git user: !`git config user.name 2>/dev/null || echo "unknown"`
- This week's commits: !`AUTHOR=\`git config user.name 2>/dev/null\`; git log --author="$AUTHOR" --since="last monday" --format="%h %s" --all 2>/dev/null | head -15 || echo "No commits found"`
- Week start: !`date -v-monday +%Y-%m-%d 2>/dev/null || date -d "last monday" +%Y-%m-%d 2>/dev/null || echo "Monday"`

**If `$ARGUMENTS` is empty or not provided:**

Generate a summary of this week's git activity.

**Usage:** `/weekly-summary [weeks-back]`

**Examples:**

- `/weekly-summary` - Current week (since Monday)
- `/weekly-summary 1` - Last week
- `/weekly-summary 2` - Two weeks ago

**Workflow:**

1. Gather commits from the specified week
2. Aggregate PRs merged and reviewed
3. Calculate productivity metrics
4. Group accomplishments by project/area
5. Generate status report format

Proceed with current week's summary.

---

**If `$ARGUMENTS` is provided:**

Generate a weekly work summary for the specified week.

## Configuration

- **Weeks Back**: `$ARGUMENTS` (0 = current week, 1 = last week, etc.)
- **Author**: Current git user (`git config user.name`)

## Steps

1. **Calculate Date Range**

   ```bash
   # Get start of week (Monday)
   # For current week: this Monday
   # For weeks back: subtract 7*N days from this Monday
   git log --since="2024-01-15" --until="2024-01-22" --author="<user>"
   ```

2. **Gather Commits Across Repos (Parallel)**

   If in a multi-repo directory, execute **all repo queries simultaneously**:

   ```bash
   # First, find all repos
   repos=$(find . -name ".git" -type d -exec dirname {} \;)
   ```

   Then for EACH repo, run these commands **in parallel**:

   - `git log` for commits
   - `git shortlog` for summary
   - Check for merged PRs

   For each repo, collect:

   - Commit count
   - Lines changed (additions/deletions)
   - Commit messages

3. **Categorize Work**

   Group commits by:
   - **Features**: `feat:` commits or new functionality
   - **Bug Fixes**: `fix:` commits or corrections
   - **Maintenance**: `chore:`, `refactor:`, `docs:`, `test:`
   - **Reviews**: If detectable from merge commits

   Also group by:
   - Project/repo
   - Area/module (from commit scope)

4. **Calculate Metrics**

   ```text
   Commits: 23
   PRs Merged: 4
   Lines Added: 1,245
   Lines Removed: 387
   Net Change: +858 lines
   Files Touched: 34
   ```

5. **Identify Key Accomplishments**

   Find significant work:
   - Large features (multiple related commits)
   - Important bug fixes
   - Completed milestones
   - Merged PRs with descriptions

6. **Generate Weekly Summary**

   ```markdown
   # Weekly Summary

   **Week of**: January 15 - 21, 2024
   **Author**: Jane Developer

   ## Highlights

   - Shipped user authentication feature (#123)
   - Fixed critical payment processing bug (#456)
   - Completed API rate limiting implementation

   ## By Category

   ### Features (8 commits)
   - User authentication with JWT tokens
   - Password reset flow
   - Session management

   ### Bug Fixes (5 commits)
   - Payment processing edge case (#456)
   - Memory leak in connection pool
   - Race condition in cache

   ### Maintenance (10 commits)
   - Refactored validation utilities
   - Updated dependencies
   - Added integration tests

   ## Metrics

   | Metric | Value |
   |--------|-------|
   | Commits | 23 |
   | PRs Merged | 4 |
   | Lines Added | 1,245 |
   | Lines Removed | 387 |
   | Files Changed | 34 |

   ## PRs Merged

   - #123: Add user authentication
   - #125: Implement rate limiting
   - #128: Fix payment bug
   - #130: Update dependencies
   ```

7. **Format for Different Audiences**

   The summary can be used for:
   - **Team standup**: Focus on highlights
   - **Manager 1:1**: Include metrics and blockers
   - **Status report**: Full detail with PRs

## Notes

- Works best with conventional commit messages
- For accurate PR data, requires GitHub remote
- Metrics are estimates based on git log
- Consider privacy when sharing detailed summaries
