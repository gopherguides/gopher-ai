---
tracker:
  kind: github
  github_status_source: label
  repository: gopherguides/gopher-ai
  status_label_prefix: "detent:"
  http_max_idle_conns: 100
  http_max_idle_conns_per_host: 32
  http_idle_conn_timeout_ms: 90000
  github_graphql_warn_remaining: 500
  github_graphql_min_remaining_reserve: 1000
  github_rest_min_remaining_reserve: 20
  github_rest_fanout_max_requests: 80
  auto_provision: true
  active_states:
    - Todo
    - In Progress
    - Rework
    - Merging
  observed_states:
    - Backlog
    - Human Review
    - Blocked
  terminal_states:
    - Done
    - Cancelled
  state_map:
    Cancelled: Done
  priority_map:
    Urgent: 1
    High: 2
    Medium: 3
    Low: 4
    No priority: null
  dependency_auto_unblock:
    enabled: true
    source_states:
      - Blocked
    target_state: Todo
    readiness: terminal_or_merged
polling:
  interval_ms: 120000
workspace:
  root: /Users/corylanou/code/detent-workspaces/gopher-ai
  source_root: /Users/corylanou/projects/gopherguides/gopher-ai
  auto_branch: true
  cleanup_idle_ttl_ms: 86400000
  cleanup_sweep_interval_ms: 600000
agent:
  max_concurrent_agents: 3
  max_turns: 20
  max_retry_backoff_ms: 300000
  max_concurrent_agents_by_state:
    Merging: 1
  dispatch_priority_by_state:
    - Merging
    - Rework
    - In Progress
    - Todo
  dispatch_priority_by_label:
    - bug
    - enhancement
  auto_promote:
    enabled: true
    quiet_seconds: 0
    optout_label: requires-human-review
    allowed_issue_labels: []
  skills:
    enabled: true
    path: .detent/skills
    max_skills_in_prompt: 50
codex:
  # Pin the model explicitly so session telemetry records it and budget
  # pricing can be computed; a bare `codex app-server` leaves the model
  # field empty in telemetry (doctor empty_model_telemetry finding).
  command: codex --config 'model="gpt-5.5"' app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
    networkAccess: true
gate:
  kind: command
  run: >-
    bash -lc './scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
  require_automated_review: false
  ci_failure_action: rework
  validator:
    enabled: false
    model: ""
    min_score: 0.8
    block_on:
      - p1
plan:
  enabled: false
  review: human
  approval_label: plan-approved
  stop: "Plan Review"
server:
  host: 0.0.0.0
  port: 4000
  kanban:
    mode: integration
hooks:
  timeout_ms: 60000
---
You are working on {{ issue.identifier }}: {{ issue.title }}.
Current Detent status: {{ issue.state }}.

Follow AGENTS.md, CLAUDE.md, and README.md in this repository. This repository
is the Gopher AI cross-platform plugin toolkit for Claude Code, OpenAI Codex
CLI, and Google Gemini CLI. Keep changes scoped to the issue and preserve the
repo's plugin architecture under `.agents/plugins`, `.claude-plugin`, and
`plugins/<name>/`.

Keep a single persistent `## Codex Workpad` issue comment updated with the
plan, validation evidence, blockers, and final handoff.

The configured validation gate is:

```sh
bash -lc './scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
```

## Required Execution Flow

Use the current Detent state as the source of truth for which section applies.

### For Todo

1. Move the issue to `In Progress`.
2. Create or update the persistent `## Codex Workpad` comment with the plan,
   acceptance criteria, validation plan, and blockers.
3. Fetch current `origin/main`, confirm this worktree is based on it, and
   confirm every `Depends on:` or `Blocked by:` issue or pull request is merged
   or otherwise terminal before coding.
4. Reproduce or confirm the reported behavior before changing code when the
   issue is a bug.
5. Implement the smallest complete change that satisfies the issue.
6. Run focused checks for touched files, then run the configured validation
   gate.
7. Commit and push the branch.
8. Open or update a pull request that references the issue.
9. Re-check pull request comments, inline review comments, and CI after the
   latest push.
10. Move the issue to `Human Review` only after the pull request is open, not a
    draft, references the issue, validation is green, and no actionable review
    comments remain.

### For In Progress

1. Re-read the issue, pull request, comments, and `## Codex Workpad`.
2. Continue from the current repository and tracker state.
3. If implementation is complete, run the full pre-review gate and move the
   issue to `Human Review` only when the gate passes.

### For Rework

1. Re-read all human, CI, and bot feedback.
2. Move the issue to `In Progress`.
3. Fix the requested changes.
4. Push updates to the pull request.
5. Run the full pre-review gate again.
6. Move the issue back to `Human Review` only when the gate passes.

### For Merging

1. Confirm `$ship` is available in the Codex environment. If it is
   unavailable, keep the issue in `Merging` and record the missing ship workflow
   as an external blocker in the `## Codex Workpad`.
2. Invoke and follow `$ship`.
3. Do not call `gh pr merge` directly outside the ship workflow.
4. End with exactly one terminal outcome:
   - pull request merged and issue moved to `Done`;
   - issue moved to `Rework` with an actionable defect;
   - issue remains in `Merging` with a concrete external blocker recorded in
     the `## Codex Workpad`.
5. Move the issue to `Done` only after the pull request is merged.
