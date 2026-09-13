---
name: complete-issue
description: "Take a GitHub issue from implementation to merged PR. Use for 'complete issue #N', 'finish this issue end-to-end', or fully autonomous issue-to-merge requests. SKIP issue startup without merge intent; use start-issue."
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
disable-model-invocation: true
---

# Complete Issue

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Autonomous pipeline: issue number -> implementation PR -> self-review ->
E2E fix-and-ship -> merged PR.

Before decisions, planning, or delegation, read
`<PLUGIN_ROOT>/lib/driver-interaction.md`. Read
`<PLUGIN_ROOT>/lib/decision-gates.md` before resolving workflow choices.
Bind `SKILL_ARGS` for `$go-workflow:complete-issue` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

Run `source "<PLUGIN_ROOT>/lib/github-rest.sh"`. Component workflows are user-only:
read their `SKILL.md` files and execute them directly with the specified child
arguments; never invoke them through another Skill tool.

## Arguments and Owner State

Read `<PLUGIN_ROOT>/skills/complete-issue/arguments.md` completely and execute
its parsing and missing-target gate. Preserve `ISSUE_NUM` and pass-through
coverage/agent flags. A missing issue number is a missing-intent gate: request
it and stop before loop initialization or any completion claim.

Read `<PLUGIN_ROOT>/skills/complete-issue/loop-state.md` completely and execute
its bootstrap, argument persistence, and re-entry checks. Complete-issue owns the
physical state file and terminal promise. Each component uses a child path in
that same file and returns structured state without a terminal marker.

Owner phase routing:

- `implementing` -> Phase 1 using `.components.start_issue.phase`
- `reviewing` -> Phase 2 on a fresh run; on successor re-entry the expired
  session-local review is void and routing continues to Phase 3
- `verifying` -> Phase 3 using `.components.e2e_verify.phase` and its nested
  active component
- `incomplete` -> report the persisted component-aware reason, emit only
  `<done>INCOMPLETE</done>`, and stop without entering Phase 3

Keep the owner `PHASE` distinct from child phases when routing. Never let a
child initialize another loop or overwrite the owner phase/result.

## Phase 1: Implementation

Set owner phase `implementing`. Read
`<PLUGIN_ROOT>/skills/complete-issue/implementation-handoff.md` completely and
execute it. It initializes the start-issue child, reads
`<PLUGIN_ROOT>/skills/start-issue/SKILL.md`, passes `$ISSUE_NUM $FLAGS`, and
propagates child failure atomically.

Read `<PLUGIN_ROOT>/skills/complete-issue/phases.md` for the full start-issue
sub-step list and implementation review command details.

> **Worktree invariant (decision-time, must stay in trunk):** after start-issue,
> every subsequent file operation and git, build, test, lint, review, and GitHub
> command targets the persisted absolute `WORKTREE_PATH`. `STATE_FILE` remains
> the normalized caller-owned path. Never rediscover either from ambient CWD.

The handoff must validate that the worktree exists, is registered under the
same original root, matches the persisted repository, and has an exact-head PR.
A mismatch is `start-issue-worktree-path-invalid` and stops incomplete.

## Phase 2: Session-Local Self-Review

Set owner phase `reviewing`. Read
`<PLUGIN_ROOT>/skills/complete-issue/self-review.md` completely and execute it.
The review must complete synchronously. Never silently skip it or leave staged
or unpushed review-owned changes at a session boundary.

When Codex is unavailable or fails, read
`<PLUGIN_ROOT>/skills/complete-issue/codex-fallback.md` completely and follow
its evidence-based recovery. Replacing an explicitly required backend is a
missing-intent gate. An ordinary timeout or failed fallback propagates
incomplete; only successor-session expired-review recovery may record void and
continue to downstream exact-head gates.

## Phase 3: E2E Verify and Ship

Set owner phase `verifying`. Read
`<PLUGIN_ROOT>/skills/complete-issue/verification-handoff.md` completely and
execute it. It initializes the E2E child, reads
`<PLUGIN_ROOT>/skills/e2e-verify/SKILL.md`, passes
`$PR_NUM fix-and-ship`, and translates structured failure into the owner
terminal result.

The E2E child owns rebase/build, embedded address-review, generated-output
recovery, browser verification, result posting, exact-head CI, and embedded ship.
It may not emit a child marker or weaken the top-level completion gate.

## Completion Criteria

Complete only when the issue is implemented with tests; a non-draft PR is
created and pushed; self-review completed with findings addressed or a
successor-session expired review is durably recorded as void and the exact
current head passes downstream CI; E2E verification and posting succeeded; and
ship merged the PR. An ordinary timeout or fallback failure does not count as
a completed review.

Only then execute **Owner Completion Result** from `verification-handoff.md`
to persist the owner complete result and emit
`<done>COMPLETE</done>`. Component failure must be propagated with its reason,
persist owner incomplete, and emit only `<done>INCOMPLETE</done>`. After 15
unsuccessful iterations, record evidence and stop incomplete.
