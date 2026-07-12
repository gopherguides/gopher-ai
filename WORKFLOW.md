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
  blocker_auto_promote:
    enabled: false
    blocker_states:
      - Backlog
      - Blocked
      - Human Review
    target_state: Todo
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
  # Spend-progress breaker DISABLED 2026-07-12 (0 = off): flat Codex
  # subscription — notional-dollar brakes were parking healthy work
  # (detent#1276). Real brakes remain: no-progress parking, session token
  # caps, provider capacity pauses.
  no_progress_spend_limit_usd: 0
  # Runaway-session guard, not a context limit; total_tokens re-counts cached
  # context every turn, so healthy sessions accrue millions of tokens quickly.
  # No max_session_context_multiplier: at 4x it capped sessions at ~1M tokens
  # (4 full-context turns) and killed legitimate work (#200 died 5x on it);
  # max_session_tokens is the sole runaway brake, matching the detent project.
  max_session_tokens: 25000000
  max_session_token_override_label: allow-large-session
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
    # gate_wait_state source: completed issues wait in In Progress for the PR
    # gate (CI green), then promote directly to Merging. Human Review is never
    # entered unless the optout label is applied or the gate wait times out.
    gate_wait_state: source
    optout_label: requires-human-review
    allowed_issue_labels: []
    rework_limit: 3
  skills:
    enabled: true
    path: .detent/skills
    max_skills_in_prompt: 50
    creation:
      enabled: true
      max_drafts_per_run: 1
codex:
  # Deliberately unpinned: the Codex CLI default manages the model, so this
  # survives provider model retirements and picks up generation upgrades
  # automatically. Telemetry resolves the effective model from the session
  # since digitaldrywood/detent#1103, so pricing attribution works without
  # a pin. Reasoning effort stays at provider default; not all models
  # accept a model_reasoning_effort override.
  command: codex app-server
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
  required_status_checks: []
  ci_failure_action: rework
  transient_ci_retry_limit: 2
  validator:
    enabled: false
    model: ""
    min_score: 0.8
    max_inline_diff_bytes: 65536
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
budget:
  # Enabled 2026-07-11 after the gopher-ai#213/#214 no-PR loop burned ~2.4M
  # tokens across ~170 sessions in one evening. Model telemetry is resolved
  # (detent#1103) and Detent ships a built-in notional pricing table
  # (internal/budget/pricing.go DefaultPricingTable) covering gpt-5.5 and
  # falling back to gpt-5.5 rates for unlisted models (gpt-5.6-sol included)
  # — approximate but real enough to pace spend and hard-stop runaway loops.
  # per_day_max_usd raised 50 -> 150 2026-07-11 PM: the same loop's spend
  # straddled the UTC day boundary, so today's cap was already blocking
  # legitimate dispatch before any of today's real work happened. Not a
  # counter to reset — spend is live off real session telemetry — so the
  # ceiling is the correct lever. Revisit down once #1224/#1229/#1211 ship.
  # per_day_max_usd raised 150 -> 250 2026-07-11 PM: #214 is the last item
  # blocking this project's plugin-marketplace release and keeps hitting the
  # daily cap; operator explicitly authorized a heavy, unattended work day.
  # Revisit down tomorrow.
  # per_issue_max_usd raised 5 -> 75 2026-07-12: #214's per-issue spend is
  # cumulative-lifetime with no reset, so the original loop's ~$58 (before
  # the fix) permanently pinned it past the $5 cap even though it has had
  # zero sessions since being unblocked this morning. It's the sole item
  # blocking this project's release. Revisit down once #214 ships.
  # per_issue_max_usd raised 75 -> 100 2026-07-12 PM: #214's lifetime spend
  # reached ~$66 after its overnight sessions, so spend + projected cost of
  # one more dispatch trips the $75 ceiling and the v0.32 hard hold (detent
  # #1251) correctly refuses it — a deliberate raise is now the designed
  # unblock lever. Runaway risk is bounded by the no-progress diff
  # fingerprint brake (detent#1232): identical no-commit sessions park after
  # 3 attempts. Still the sole release blocker. Revisit down once #214 ships.
  # DISABLED 2026-07-12 PM (operator decision): flat Codex subscription —
  # these USD caps are notional and spent the whole day blocking the sole
  # release blocker (#214) over fake dollars, including charging this
  # project the entire fleet's spend (detent#1279). Real constraints on
  # subscription auth: provider rate windows (capacity pauses) and
  # outcome-based brakes. Re-enable only behind an auth-aware design.
  enabled: false
  per_day_max_usd: 600
  per_issue_max_usd: 100
  refusal_cooldown_seconds: 3600
  pricing_path: priv/pricing/models.yaml
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
