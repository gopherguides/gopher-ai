You are working on {{ issue.identifier }}: {{ issue.title }}.
Current Detent status: {{ issue.state }}.

Follow AGENTS.md, CLAUDE.md, and README.md in this repository. This repository
is the Gopher AI cross-platform plugin toolkit for Claude Code, OpenAI Codex
CLI, and Google Gemini CLI. Keep changes scoped to the issue and preserve the
repo's plugin architecture under `.agents/plugins`, `.claude-plugin`, and
`plugins/<name>/`.

Keep a single persistent `## Codex Workpad` issue comment updated with the
plan, validation evidence, blockers, and final handoff. Every Workpad update
must include one `detent-status` fenced block. Detent reads blocker and
human-action declarations from that block; narrative sentences are never read
as blockers.

```detent-status
schema: 1
status: in_progress
blockers: []
human_action: null
```

For dependency blockers, use this order:

1. Create GitHub's native `blocked_by` dependency relation.

```sh
BLOCKED_NUMBER=<blocked-issue-number>
BLOCKER_NUMBER=<blocker-issue-number>
BLOCKER_ID="$(gh api repos/{owner}/{repo}/issues/$BLOCKER_NUMBER --jq '.id')"
gh api --method POST "repos/{owner}/{repo}/issues/$BLOCKED_NUMBER/dependencies/blocked_by" -F issue_id="$BLOCKER_ID"
```

2. Declare the blocker in the Workpad status block.

```detent-status
schema: 1
status: blocked
blockers:
  - ref: "owner/repo#123"
    reason: "waiting for the dependency to merge"
human_action: null
```

3. Legacy fallback during the deprecation window: if native dependencies are
   unavailable and the project has not migrated, keep a machine-readable
   issue-body line such as `Blocked by: #123` or `Depends on: owner/repo#123`.

The configured validation gate is:

```sh
bash -lc './scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
```

## Required Execution Flow

Use the current Detent state as the source of truth for which section applies.

### For Todo

1. Move the issue to `In Progress`.
2. Create or update the persistent `## Codex Workpad` comment with the plan,
   acceptance criteria, validation plan, and the `in_progress` `detent-status`
   block shown above.
3. Fetch current `origin/main`, confirm this worktree is based on it, and
   confirm every native dependency relation, `detent-status` blocker, and
   issue-body `Depends on:` reference is merged or otherwise terminal before
   coding.
4. Reproduce or confirm the reported behavior before changing code when the
   issue is a bug.
5. Implement the smallest complete change that satisfies the issue.
6. Run focused checks for touched files, then run the configured validation
   gate.
7. Commit and push the branch.
8. Open or update a pull request that references the issue.
9. Re-check pull request comments, inline review comments, and CI after the
   latest push.
10. Do NOT move the issue to `Human Review`. Leave the issue in `In Progress`
    and update the Workpad `detent-status` block to `status: complete` with
    `blockers: []` once the pull request is open, not a draft, references the
    issue, validation is green, and no actionable review comments remain.
    Detent auto-promotes the issue directly to `Merging` when the PR gate
    (CI) is green.

### For In Progress

1. Re-read the issue, pull request, comments, and `## Codex Workpad`, including
   the `detent-status` block.
2. Continue from the current repository and tracker state.
3. If implementation is complete, run the full pre-review gate, then update
   the Workpad block to `status: complete` with `blockers: []` and
   `human_action: null` only when the gate passes. Do NOT move the issue to
   `Human Review`; leave it in `In Progress` and let Detent auto-promote it
   to `Merging` once the PR gate is green.

### For Rework

1. Re-read all human, CI, and bot feedback.
2. Move the issue to `In Progress`.
3. Fix the requested changes.
4. Push updates to the pull request.
5. Run the full pre-review gate again.
6. When the gate passes, update the Workpad `detent-status` block to
   `status: complete` and leave the issue in `In Progress`; Detent
   auto-promotes it back to `Merging` once the PR gate is green. Do NOT move
   it to `Human Review`.

### For Merging

1. Confirm `$go-workflow:ship` is available in the Codex environment. If it is
   unavailable, keep the issue in `Merging` and record the missing ship
   workflow as `human_action` in the `detent-status` block.
2. Invoke and follow `$go-workflow:ship`.
3. Do not call `gh pr merge` directly outside the ship workflow.
4. End with exactly one terminal outcome:
   - pull request merged and issue moved to `Done`;
   - issue moved to `Rework` with an actionable defect;
   - issue remains in `Merging` with a concrete external blocker recorded in
     the `detent-status` block and described in the `## Codex Workpad`.
5. Move the issue to `Done` only after the pull request is merged.
