---
name: review-deep
description: "Deep-review a PR or branch with issue and repo context, then fix and commit actionable findings; PR-backed runs push new review commits by default. Use for 'review my changes', 'check this PR', or post-implementation quality/spec review requests. SKIP existing human/bot review comments that need replies/thread resolution; use address-review."
argument-hint: "[PR-number|--issue <N>] [--post] [--scope <hint>] [--no-fix] [--no-commit] [--push|--no-push]"
---

# Deep Review: Full-Context Code Review + Fix

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before decisions or delegation, read `<PLUGIN_ROOT>/lib/driver-interaction.md`.
Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving scope or delivery.
Bind `SKILL_ARGS` for `$go-workflow:review-deep` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

## Step 0: Arguments and Action Contract

Read `<PLUGIN_ROOT>/skills/review-deep/arguments.md` completely and execute it.
It parses PR/issue targets, post and scope hints, and independent
`FIX_CHANGES`, `COMMIT_CHANGES`, and `PUSH_CHANGES` controls.

Action matrix:

- PR-backed default: fix, commit, push, and verify local/remote head equality.
- Branch-only default: fix and commit locally without push.
- `--no-fix`: report only; no review commit or push.
- `--no-commit`: leave owned fixes uncommitted and disable auto-push.
- `--no-push`: commit locally and report the unchanged remote.
- `--push`: push explicitly, but fail when owned fixes remain uncommitted.

A commit, push, or remote-head verification failure is incomplete, never a
successful review.

## Steps 1-2: Scope and Context

Read `<PLUGIN_ROOT>/skills/review-deep/scope-discovery.md` completely and
execute PR detection, associated-HEAD fallback, base selection, and context
routing. API failure is incomplete discovery, not evidence of no PR.

Then read `<PLUGIN_ROOT>/skills/review-deep/context-gathering.md` completely
and gather PR metadata, linked issues, unresolved threads, inline comments,
pending reviews, and repository guidelines. For `--issue`, gather issue-only
context; with neither target, perform a diff-only review. Apply the documented
context size guard and bot-noise filtering.

## Steps 3-4: Coverage Plan and Static Analysis

Read `<PLUGIN_ROOT>/skills/review-deep/static-analysis.md` completely and
execute it. Generate the correct base/uncommitted diff, preserve `SCOPE_HINT`,
run the shared adaptive planner in
`<PLUGIN_ROOT>/lib/review-planning.md`, and complete every planned unit plus
the coordinated cross-cutting pass.

For Go changes, collect vet, staticcheck, and race-test output as review
evidence; these commands inform findings rather than independently blocking.
For visual work, read `<PLUGIN_ROOT>/lib/screenshot-evidence.md`, initialize
the manifest, inspect each capture, and preserve evidence for reporting.

## Step 5: Ordered Review Pipeline

Read `<PLUGIN_ROOT>/skills/review-deep/review-criteria.md` completely. Review
every planned unit for correctness, security, performance, maintainability, Go
idioms, tests, documentation, and breaking changes.

In order:

1. Map each issue/PR acceptance criterion to implementation and tests; identify
   missing requirements and scope creep.
2. Re-evaluate each unresolved review thread against the current diff.
3. Incorporate static-analysis and screenshot evidence.
4. Run the cross-cutting pass, then verify, deduplicate, confidence-score, and
   rank findings against the checkout.
5. Read `<PLUGIN_ROOT>/skills/review-deep/output-format.md` for the exact
   findings, spec-compliance, review-status, score, and recommendation formats.

## Step 6: Fix, Verify, Commit, and Push

Read `<PLUGIN_ROOT>/skills/review-deep/fix-and-verify.md` completely and
execute it end-to-end. Process P0 through P3; skip invalid, pre-existing, or
intentional findings and P3 findings below the confidence threshold. Make
minimal fixes, add tests for observable changes, and track only review-owned
files.

Review and fix all findings in the current context; never delegate based on
finding count. Verify the applicable build, tests, and lint.
Pass only owned files to `review-deep-post-fix.sh` and apply commit/push flags
independently.

## Step 7: Report and Optional PR Post

Read **Step 7: Final Summary and Delivery** in
`<PLUGIN_ROOT>/skills/review-deep/output-format.md` and execute it using the
structured helper result. If the helper failed, do not render a completed review
or imply fixes reached the remote.

Post only when `--post` or the original request explicitly authorizes a PR
comment. Otherwise keep the report in the response. This is driver-resolvable;
state Decision, Evidence, and Rationale without requesting redundant input.

## Completion Contract

A completed review reports all findings, fixes/skips with reasons, verification
status, commit/push result, local/remote heads, quality score, and one of
`APPROVE|REQUEST_CHANGES|COMMENT`. Never report success after an incomplete
scope lookup, fix verification, commit, push, or remote-head check.
