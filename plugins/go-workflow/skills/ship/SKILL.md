---
name: ship
description: "Ship a PR through local verification, push, CI, review, and merge without admin override. Use for 'ship', 'ship it', or 'push and merge'. SKIP if the user only wants a PR opened; use create-pr."
argument-hint: "[--llm codex|gemini|ollama|fable] [--passes <n>] [--no-merge] [--skip-coverage] [--coverage-threshold <n>] [--tier flex|standard|priority]"
disable-model-invocation: true
---

# Ship PR

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before decisions or delegation, read `<PLUGIN_ROOT>/lib/driver-interaction.md`.
Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving any workflow choice.
Bind the invocation arguments as `SKILL_ARGS` for `$go-workflow:ship` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

Run `source "<PLUGIN_ROOT>/lib/github-rest.sh"`. Routine PR metadata, formal reviews,
CI, mergeability, and squash merge use its REST helpers. Use GraphQL only for
review threads, closing-issue references, or required merge queues.

## Setup, Arguments, and Re-entry

Read `<PLUGIN_ROOT>/lib/ship/bootstrap.md` completely and execute the state
bootstrap. Standalone ship owns one canonical state file; embedded ship uses the
caller file and child path, never creates another loop, changes root promises,
or emits a terminal marker.

Parse `SKILL_ARGS` into `LLM_CHOICE` (default `codex`), `MAX_PASSES`
(default `3`), `NO_MERGE`, `SKIP_COVERAGE`, `COVERAGE_THRESHOLD`
(default `60`), `GEMINI_TIER`, and `LLM_EXPLICIT`. Supported LLMs are
`codex|gemini|ollama|fable`; tier is `flex|standard|priority`.
`--skip-coverage` never waives coverage for changed source files.

Read `<PLUGIN_ROOT>/lib/ship/state-fields.md` completely and persist every
argument and workflow field. Then read `<PLUGIN_ROOT>/lib/ship/reentry.md`
completely and execute its re-entry check. Its phase routing and expired-review
recovery are authoritative.

If this skill or any supporting file sets `WORKFLOW_RESULT=INCOMPLETE`, execute
**Hard Invariant Failure** from `reentry.md` and stop. Embedded ship returns
structured incomplete state without a marker; standalone ship persists and
emits only `<done>INCOMPLETE</done>`.

Phase routing:

- `reviewing` -> expired-review recovery, then push
- `review-required` -> local review
- `fixing|verifying|coverage-check|e2e-testing` -> corresponding local-review step
- `pushing` -> push and PR creation
- `ci-watch` -> exact-head CI
- `bot-watching` -> bot watch
- `addressing` -> address feedback
- `merging` -> final merge

## Context and Prerequisites

Read `<PLUGIN_ROOT>/lib/ship/context.md` completely and execute PR, branch, and
worktree-ownership discovery. Shipping the default branch is a hard invariant.
Include dirty changes only when ownership and fresh validation are unambiguous;
otherwise preserve unrelated work or stop incomplete.

Read `<PLUGIN_ROOT>/lib/ship/prerequisites.md` when resolving the review
backend. An unavailable unpinned default may use its evidence-based fallback;
replacing an explicitly selected backend is a missing-intent gate.

## Phase 1: Local Review and Verification

Read `<PLUGIN_ROOT>/lib/ship/local-review.md` completely and execute Steps 5-8.
It owns LLM review/fix passes, build/test/lint, generation drift, the final-pass
coverage gate, non-UI E2E skip, scoped staging, commit, and loop decision.
UI-visible changes require passing E2E; missing browser tooling or an unavailable
server blocks before push or merge.

## Phase 2: Push and PR

Set phase `pushing`. Read `<PLUGIN_ROOT>/lib/ship/push-and-pr.md` completely.
Push the explicit head, ensure a non-draft PR exists, then persist the published
head SHA and bot-review baseline.

## Phase 3: Exact-Head CI

Set phase `ci-watch`. Read `<PLUGIN_ROOT>/lib/ship/ci-watch.md` completely.
No checks, prior-head checks, or a concurrent head shift are never passing CI.
Every completion claim must use terminal successful checks for the exact
published head.

## Phase 4: Bot Review

Set phase `bot-watching`. Read `<PLUGIN_ROOT>/lib/ship/bot-watch.md`
completely. Detect registered bots from REST reviews/comments, GraphQL threads,
and exact-head statuses; apply its bounded startup wait and approval rules.

## Phase 5: Address Feedback

Set phase `addressing`. Read `<PLUGIN_ROOT>/lib/ship/address-bots.md`
completely. It owns rebase-or-abort, the embedded address-review Steps 2-11
boundary, baseline-before-push ordering, and the return to exact-head CI.

## Phase 6: Merge

Set phase `merging`. Read `<PLUGIN_ROOT>/lib/ship/merge.md` completely.
Never use admin override or bypass branch protection. Use the configured merge
strategy (squash when available), expected head SHA, final CI/thread/human-review
checks, and merge queue only when required.

## Completion Contract

Return shipped only after fresh evidence proves: local review is clean/maxed or
durably recorded as `void`/`skipped` for an allowed session reason and the exact
current head passes CI; applicable coverage and E2E passed; changes are pushed;
a non-draft PR exists; detected bots approve or none apply; no unresolved or
human-requested changes remain; and the PR merged (or `--no-merge` was supplied).
An unrecorded timeout, error, or early exit never satisfies review completion.

Standalone success persists then emits `<done>SHIPPED</done>`. Embedded success
persists its structured child result and emits no marker. After 15 unsuccessful
iterations, persist incomplete evidence and stop; never bypass a completion
criterion.
