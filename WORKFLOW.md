You are working on {{ issue.identifier }}: {{ issue.title }}.
Current Detent status: {{ issue.state }}.

Follow AGENTS.md, CLAUDE.md, and README.md. Keep changes scoped to the issue and
preserve the plugin architecture under `.agents/plugins`, `.claude-plugin`, and
`plugins/<name>/`.

## Detent Protocol

Keep one persistent `## Codex Workpad` issue comment updated with the plan, validation
evidence, blockers, and final handoff. Every update must contain one `detent-status`
fenced block; Detent reads blockers and human actions only there, never from prose.

```detent-status
schema: 1
status: in_progress
blockers: []
human_action: null
```

Before coding, resolve every native dependency, Workpad blocker, and issue-body
`Depends on:` reference. For a dependency blocker, create GitHub's native
`blocked_by` relation first, then set Workpad `status: blocked` and list its
`ref` and `reason`. Use an issue-body reference only as a legacy fallback.

Run the authoritative validation command from `gate.run` in `detent.yaml`; never duplicate it here.

## State Flow

Use the current Detent state as the source of truth for which section applies.

### For Todo

1. Move the issue to `In Progress`.
2. Initialize the Workpad with the plan, acceptance criteria, validation plan, and `in_progress` status.
3. Fetch `origin/main`, confirm the Detent worktree base, resolve dependencies, then follow `$go-workflow:start-issue <number>`.
4. Run focused checks and the configured validation gate.
5. Follow `$go-workflow:commit`, `$go-workflow:create-pr`, and `$go-workflow:address-review`.
6. Leave the issue in `In Progress`. Set Workpad `status: complete` with no blockers or human action only when the PR is non-draft, references the issue, validation and current-head CI are green, and no actionable review remains. Detent auto-promotes directly to `Merging`; never use `Human Review`.

### For In Progress

Re-read the issue, PR, comments, and Workpad, then continue from the current state.
When implementation is complete, run the full gate and apply Todo's completion rule.

### For Rework

Re-read all human, CI, and bot feedback, move the issue to `In Progress`, and follow
`$go-workflow:address-review`. Rerun the full gate and apply Todo's completion rule.

### For Merging

1. Follow `$go-workflow:ship`; never call `gh pr merge` outside it. If unavailable,
   remain in `Merging` and record `human_action`.
2. End with exactly one terminal outcome:
   - PR merged and issue moved to `Done`;
   - issue moved to `Rework` with an actionable defect;
   - issue remains in `Merging` with an external blocker recorded in the
     `detent-status` block and Workpad.
3. Move the issue to `Done` only after the pull request is merged.
