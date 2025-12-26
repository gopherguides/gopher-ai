---
argument-hint: "[hours|days]"
description: "Generate standup notes from recent git activity"
model: haiku
allowed-tools: ["Bash(git:*)", "Bash(date:*)", "Read", "Glob", "Grep"]
---

## Context

- Current git user: !`git config user.name`
- Current branch: !`git branch --show-current`
- Today: !`date +%A`
- Recent commits (24h): !`git log --author="$(git config user.name)" --since="24 hours ago" --format="%h %s" --all 2>/dev/null | head -10`

**If `$ARGUMENTS` is empty or not provided:**

Generate a standup for the default timeframe (24 hours, or 72 hours on Mondays).

**Usage:** `/standup [timeframe]`

**Examples:**

- `/standup` - Last 24 hours (72h on Mondays)
- `/standup 48h` - Last 48 hours
- `/standup 3d` - Last 3 days
- `/standup "since monday"` - Since Monday

**Workflow:**

1. Scan git commits for your user
2. Group by type (features, fixes, refactors)
3. Identify in-progress work and blockers
4. Generate copy-paste ready standup report

Proceed with default 24h timeframe (or 72h if today is Monday).

---

**If `$ARGUMENTS` is provided:**

Generate a standup summary from recent git activity using the specified timeframe.

## Security Validation

Before using `$ARGUMENTS` in git commands, validate the timeframe format:
- Valid patterns: `[0-9]+[hdwm]` (e.g., "48h", "3d", "1w", "2m")
- Valid patterns: `"since (monday|tuesday|wednesday|thursday|friday|saturday|sunday|yesterday)"`
- Reject any input containing shell metacharacters: `;`, `|`, `&`, `$`, backticks, `(`, `)`, `>`, `<`

If validation fails, display: "Invalid timeframe format. Use examples like '48h', '3d', or 'since monday'"

## Configuration

- **Timeframe**: `$ARGUMENTS` (examples: "48h", "3d", "since monday")
- **Author**: Current git user (`git config user.name`)

## Steps

1. **Identify Author and Timeframe**
   - Get the current git user: `git config user.name`
   - Parse timeframe from `$ARGUMENTS` or default to 24 hours
   - For Monday standups, automatically look back to Friday (72h)

2. **Gather All Git Data (Parallel)**

   Execute ALL these commands **simultaneously** in a single response:

   | Data | Command |
   |------|---------|
   | Commits | `git log --author="<author>" --since="<timeframe>" --format="%h %s" --all` |
   | Current branch | `git branch --show-current` |
   | Uncommitted | `git status --porcelain` |
   | Recent branches | `git branch --sort=-committerdate --format='%(refname:short)' \| head -5` |
   | Stash | `git stash list` |
   | Behind main | `git log HEAD..origin/main --oneline \| head -3` |

   Run all 6 commands in parallel, then analyze results together.

3. **Categorize Commits**

   Group commits by type:

   - **Features**: commits starting with `feat:` or containing "add", "implement", "create"
   - **Fixes**: commits starting with `fix:` or containing "fix", "resolve", "correct"
   - **Refactors**: commits starting with `refactor:` or containing "refactor", "clean", "improve"
   - **Other**: documentation, tests, chores, etc.

4. **Generate Standup Report**

   Format the output as:

   ```text
   ## Standup - [date]

   ### Yesterday (Completed)
   - [Summarize completed work from commits]
   - [Group related commits into single bullet points]

   ### Today (Planned)
   - [Infer from in-progress branches and uncommitted work]
   - [Any obvious next steps from recent commits]

   ### Blockers
   - [Any merge conflicts, stale branches, or issues detected]
   - [Or "None" if no blockers found]
   ```

5. **Output**

   - Display the formatted standup report
   - Keep it concise: aim for 3-5 bullets per section max
   - Merge related commits into cohesive summaries (don't list every commit)
   - Use action verbs: "Implemented...", "Fixed...", "Refactored..."

## Notes

- If no commits found in timeframe, note that and check for uncommitted work
- For multi-repo directories, run in each git repo found and aggregate
- Focus on meaningful work, skip trivial commits like "wip", "typo", "merge branch"
- The report should be copy-paste ready for Slack, Teams, or JIRA
