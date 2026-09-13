---
name: address-review
description: "Address pull request review feedback from humans or bots. Use when existing comments, requested changes, unresolved review threads, or CodeRabbit/codex review findings need code fixes, verification, push updates, and thread resolution. SKIP fresh code-review requests with no existing feedback; use review-deep."
argument-hint: "[PR-number] [--no-watch]"
disable-model-invocation: true
---

# Address PR Review Comments

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before decisions or delegation, read `<PLUGIN_ROOT>/lib/driver-interaction.md`.
Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving any workflow choice.
Bind `SKILL_ARGS` for `$go-workflow:address-review` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

Run `source "<PLUGIN_ROOT>/lib/github-rest.sh"`.

## Entry and Durable State

Read `<PLUGIN_ROOT>/skills/address-review/entry.md` completely and execute
argument parsing, numeric validation, current-branch PR auto-detection, and
repository resolution. `--no-watch` disables only Step 12. If no PR is found,
use the missing-intent gate and stop before loop initialization or completion.

Read `<PLUGIN_ROOT>/skills/address-review/loop-management.md` completely and
execute **Embedded Workflow Contract**, **Loop Initialization**, and **Re-entry
Check**. Standalone address-review owns its loop; embedded address-review uses
the caller state file and child path, never changes root promises or emits a
terminal marker.

If this skill or a supporting file sets `WORKFLOW_RESULT=INCOMPLETE`, execute
**Hard Invariant Failure** from `loop-management.md` and stop. The embedded
branch returns structured incomplete state without a marker.

A resumed standalone `watching` phase in watch mode skips to Step 12. In
`--no-watch` mode it clears the phase and performs a full fix cycle.

## Context and Checkout

Read `<PLUGIN_ROOT>/skills/address-review/setup-and-discovery.md` completely.
Gather REST PR context, detect review bots from REST reviews and GraphQL threads,
and preserve matched logins in `DETECTED_BOTS`.

Read `<PLUGIN_ROOT>/skills/address-review/checkout-rebase.md` completely and
execute Step 1. Use the REST-declared PR head, preserve fork/base metadata,
rebase only when behind, push with lease when required, and re-check current-head
CI. An unresolved rebase conflict is incomplete.

## Step 2: Fetch Feedback

Read `<PLUGIN_ROOT>/skills/address-review/fetch-feedback.md` completely.
Gather resolvable GraphQL threads and REST `CHANGES_REQUESTED` reviews.

## Steps 3-9: Fix Cycle

Read `<PLUGIN_ROOT>/skills/address-review/fix-cycle.md` completely and execute
the full categorize/fix/test/verify/commit/CI/reply/resolve cycle.

A clean review sets and persists `REVIEW_CLEAN=true`, skips only mutation,
reply, resolution, and re-review actions, but still performs local verification,
exact-head CI, and Step 11. For feedback, make minimal fixes, add tests for
observable behavior, stage only owned files, push, reply with durable behavior
descriptions, and resolve only Group A threads after verification.

## Step 10: Re-review

Read `<PLUGIN_ROOT>/skills/address-review/bot-registry.md` completely and
execute its data-driven re-review procedure only for detected reviewers that
left applicable feedback.

## Step 11: Completion Check

Read `<PLUGIN_ROOT>/skills/address-review/completion-check.md` completely and
execute it. Completion requires the PR head to equal `EXPECTED_REVIEW_HEAD`
(or current local HEAD), zero unresolved threads, and successful exact-head CI.
Metadata failure, missing checks, API failure, or a head shift is incomplete.

## Step 12: Bot Watch

Skip when `WATCH_MODE=false` or no registered review bot was detected.
Otherwise read `<PLUGIN_ROOT>/skills/address-review/watch-loop.md` completely
and execute its bounded quiet-period, approval, re-trigger, and exhaustion rules.

## Standalone and Embedded Completion

Embedded consumers execute Steps 2-11 only and return control to the caller
after Step 11.
They preserve `REVIEW_CLEAN` and durable `review_clean`, and emit no terminal
marker. Ship or E2E remains the top-level owner of later CI, bot watch, posting,
merge, and completion gates.

Standalone `--no-watch` completes after rebase, local verification, exact-head
CI, Step 11, and all applicable feedback replies/resolutions/re-review requests.
Default watch mode additionally requires every detected review bot to signal
approval according to `bot-registry.md`.

Only then execute **Completion Criteria** from `completion-check.md`.
Standalone emits
`<done>COMPLETE</done>`; embedded address-review returns
`ADDRESS_REVIEW_RESULT=complete` without a marker. After 15 unsuccessful
iterations, persist incomplete evidence and stop.
