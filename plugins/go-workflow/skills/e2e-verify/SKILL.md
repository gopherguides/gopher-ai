---
name: e2e-verify
description: "Run end-to-end PR verification with browser testing. Use before merge or in fix-and-ship mode when the user asks to verify a PR, run E2E, browser-test, or visually check UI changes. SKIP backend-only checks with no browser/UI path; use review-deep or ship as appropriate."
argument-hint: "[PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
disable-model-invocation: true
---

# E2E Verify

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before decisions or delegation, read `<PLUGIN_ROOT>/lib/driver-interaction.md`.
Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving a target or workflow
choice. Bind `SKILL_ARGS` for `$go-workflow:e2e-verify` by reading
`<PLUGIN_ROOT>/lib/skill-arguments.md` with this compatibility payload:

<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

Run `source "<PLUGIN_ROOT>/lib/github-rest.sh"`.

## Non-Negotiable Visual Gate

Every screenshot must be read with vision, compared to the PR/issue spec,
described, and checked for discrepancies. DOM, console, and network checks
supplement visual inspection; they never replace it.

UI-visible failure blocks labels and shipping. A missing browser tool, failed
server, uninspected screenshot, partial result, or visual failure is not a
verified result.

## Setup and Durable State

Read `<PLUGIN_ROOT>/skills/e2e-verify/setup.md` completely and execute its
argument parsing and PR resolution. It accepts exactly these modes:
`verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship`.

Read `<PLUGIN_ROOT>/skills/e2e-verify/loop-state.md` completely and execute,
in order:

1. **Embedded Workflow Contract**
2. **Bootstrap Block**
3. **Persist Arguments Block**
4. **Re-entry Check**
5. **Terminal Re-entry**

If this skill or any supporting file sets `WORKFLOW_RESULT=INCOMPLETE`, execute
**Hard Invariant Failure** from `loop-state.md` and stop. Never continue to
browser testing, add labels, invoke ship, or claim verification on that path.

Phase → step routing:

- `rebasing` → Steps 1-2
- `building` → Step 2
- `addressing` → Step 3
- `investigating` → Step 4
- `e2e-testing` → Step 5
- `posting` → Step 6
- `shipping` → Step 7
- `e2e-failed` → report the persisted reason and stop. Embedded E2E returns
  structured failure; standalone E2E emits only `<done>E2E_FAIL</done>`.

## Standalone and Embedded Ownership

Standalone E2E owns its loop and marker. Embedded E2E uses the caller's state
file and child path, never initializes another loop or changes root promises,
and returns only a structured result without a marker.

## Mode Summary

| Mode | Steps | Finish |
|---|---|---|
| `verify` | 1-2, 5-6 | Report |
| `fix-and-verify` | 1-3, 5-6 | Label and report |
| `investigate` | 1-2, 4-6 | Report findings without a label |
| `ship-prep` | 1-2, 5-6 | Label and report |
| `ship` | 1-2, 5-7 | Run ship |
| `fix-and-ship` | 1-3, 5-7 | Label, watch CI, run ship |

## Steps 1-2: Rebase and Build

Set phase to `rebasing`. Read
`<PLUGIN_ROOT>/skills/e2e-verify/rebase-and-build.md` completely and execute
the full procedure. It owns base detection, rebase/lease-push, current-head CI,
generation, build, tests, lint, and generated-file drift.

Then read **Persist Build Result** in
`<PLUGIN_ROOT>/skills/e2e-verify/loop-state.md` and execute it. Stop if build
verification failed.

## Step 3: Review and Generated Output

Only for `fix-and-verify` and `fix-and-ship`. Read
`<PLUGIN_ROOT>/skills/e2e-verify/review-and-generated-output.md` completely
and execute the full procedure. It owns embedded address-review Steps 2-11,
empty-index enforcement, generated-output transaction recovery/commit/push,
post-fix verification, and exact final-head review verification.

## Step 4: Investigate

Only for `investigate`. Read
`<PLUGIN_ROOT>/skills/e2e-verify/investigate.md` completely and execute it.
Do not fix findings in this mode.

## Step 5: Browser E2E

Set phase to `e2e-testing`, refresh PR metadata, and read
`<PLUGIN_ROOT>/skills/e2e-verify/e2e-test-execution.md` completely. Execute
its full procedure, including per-route navigate, stabilize, screenshot, READ,
spec comparison, evidence recording, and cleanup.

Then read **Persist E2E Result** in
`<PLUGIN_ROOT>/skills/e2e-verify/loop-state.md` and execute it.

## Step 6: Post Results

Set phase to `posting`. Read
`<PLUGIN_ROOT>/skills/e2e-verify/pr-results-comment.md` completely and execute
its structured result posting and mode-specific label rules.

## Step 7: Finish

Read `<PLUGIN_ROOT>/skills/e2e-verify/mode-finish.md` completely and execute
Step 7.0 before any mode action. It owns the E2E gate, labels, exact-head CI
watch, direct ship workflow handoff, and final result persistence.

The gate is mandatory: UI-visible failures return `e2e-fail` after posting,
without labels or ship. Standalone E2E persists then emits
`<done>E2E_FAIL</done>`; embedded E2E persists structured failure and emits
no marker.

## Completion Contract

A verified result requires rebase, local checks, applicable review, passing UI
E2E (or a non-UI skip), posted results, and the mode finish action. Apply the
exact result matrix and completion mechanics in `mode-finish.md`.

Standalone success persists then emits `<done>VERIFIED</done>`. Embedded
success persists `verified` and returns without a marker. Never invoke ship or
add labels after `fail`, `partial`, `skipped-server-failed`,
`missing-browser-tooling`, or `uninspected-screenshots`.

After 15 unsuccessful iterations, record the evidence and stop incomplete.
Never bypass browser verification or completion criteria.
