---
name: start-issue
description: "Start implementation of a GitHub issue: fetch context, prepare worktree flow, implement with TDD, verify, and submit PR. Use for 'start issue #N', issue URLs, or requests to begin issue work. SKIP fully autonomous issue-to-merge requests; use complete-issue."
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
disable-model-invocation: true
---

# Start Issue

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before decisions, planning, or delegation, read
`<PLUGIN_ROOT>/lib/driver-interaction.md`. Read
`<PLUGIN_ROOT>/lib/decision-gates.md` before resolving any workflow choice.
Bind `SKILL_ARGS` for `$go-workflow:start-issue` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

## Setup and Durable State

Read `<PLUGIN_ROOT>/lib/start-issue/setup.md` completely. Execute **Empty
Arguments**, **Output Durability**, **Clear Stale Worktree State**, **Security
Validation & Flag Parsing**, and **Surface Dispatch Decision** in order.
A missing issue number is a missing-intent gate: request it and stop before loop
initialization or any completion claim.

After parsing, use only numeric `ISSUE_NUM`. Preserve `SKIP_COVERAGE`,
`COVERAGE_THRESHOLD` (default `60`), and `NO_AGENTS`.
`--skip-coverage` never waives coverage for changed source.

Read `<PLUGIN_ROOT>/lib/start-issue/loop-state.md` completely and execute
**Embedded Workflow Contract** and **Loop Initialization**. Standalone
start-issue owns its loop; embedded start-issue uses the caller file and child
path, never changes root promises or emits a child terminal marker.

Then execute **Context** from `setup.md` to fetch the issue, labels, comments,
default branch, checkout, and registered worktrees.

## Workspace Before Planning

Read `<PLUGIN_ROOT>/lib/start-issue/workspace.md` completely and execute it
before planning. Worktree selection is driver-resolvable; an existing isolated
worktree is reused without another worktree or branch-format gate. If creation
is selected, read `<PLUGIN_ROOT>/lib/start-issue/worktree-create.md` completely
and persist its absolute output before planning. Copying environment files
requires explicit consent.

Every repository command and file operation must explicitly target the resolved
`WORKTREE_PATH`. Never commit to the default branch.

## Issue Classification

Classify from labels, title, body, comments, and acceptance criteria, checking
labels first.
Bug indicators include `bug|fix|defect|error|regression|crash`; feature
indicators include `enhancement|feature|add|support|enable`. If semantics remain
ambiguous after all evidence, use the missing-intent gate and stop before branch
creation or implementation.

## Implementation Selection

For `NO_AGENTS=true`, or on Codex without the required native
`explorer`/`worker`/`default` delegation profiles, read
`<PLUGIN_ROOT>/lib/start-issue/manual-workflow.md` completely and execute its
single-session flow.

Otherwise read
`<PLUGIN_ROOT>/lib/start-issue/orchestrated-workflow.md` completely and execute
its full procedure with the active surface binding. Start-issue agent dispatch
is delegation, not another skill invocation.

Both flows preserve this order: explore/design, TDD red before implementation,
minimal green, build/test/lint, coverage, security review, scoped commit/push,
non-draft PR creation, and current-head CI. Bugs also perform duplicate
detection. Features resolve approach from requirements, repository patterns,
reversibility, and risk.

## Verification and Submission Contract

Before commit, push, or PR creation, fresh evidence must show the project build
and tests pass, configured lint passes (when installed), coverage is verified
for changed source, and security review is complete. Read
`<PLUGIN_ROOT>/lib/coverage/coverage-verification.md` for coverage.

After publishing, read
`<PLUGIN_ROOT>/lib/start-issue/ci-monitoring.md` completely and require
successful REST monitoring for the exact pushed head. Prior-head or absent
checks are not passing evidence.

If any supporting file produces an incomplete result, execute **Workflow Result
Contract** from `loop-state.md` and stop. Embedded runs persist structured
incomplete state without a marker; standalone runs persist then emit only
`<done>INCOMPLETE</done>`.

## Completion Criteria

Complete only when implementation addresses the issue, tests and build pass,
coverage is verified or source-free, configured lint passes, changes are
committed and pushed, a non-draft PR exists, and exact-head CI is green.

Execute **Successful Result** from `loop-state.md` only after all criteria
hold. Embedded success returns structured state without a marker; standalone
success emits `<done>COMPLETE</done>`. After 15 unsuccessful iterations,
persist incomplete evidence and stop.
