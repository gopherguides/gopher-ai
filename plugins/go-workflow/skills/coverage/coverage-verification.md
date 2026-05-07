# Coverage Verification (Shared Reference)

This document is referenced by both `/ship` and `/start-issue`. It's a router:
each step (A through F) gives the contract — what must be true on entry, what
must be true on return — and points to the sibling that owns the implementation.
Follow Steps A through F using the parameters provided by the calling command.

## Prerequisites

The calling command MUST set these variables before invoking this workflow:

| Variable | Description | Example |
|----------|-------------|---------|
| `BASE_BRANCH` | Branch to diff against | `origin/main` |
| `STATE_FILE` | **Absolute path** to the loop state JSON file | `/path/to/.local/state/ship.loop.local.json` |
| `SKIP_COVERAGE` | Whether to skip coverage entirely | `true` or `false` |
| `COVERAGE_THRESHOLD` | Minimum coverage percentage for changed files | `60` |

**Worktree note:** When running in a worktree, `STATE_FILE` MUST be an absolute path to the state file (which lives in the original repo's `.local/state/` directory, not the worktree). Coverage artifacts (`.local/state/coverage.out`) are written relative to the current working directory — ensure `.local/state/` exists via `mkdir -p .local/state` before running coverage commands.

## State-file fields written

After this workflow returns, the state file holds these keys (callers read them
to render summary lines):

| Field | Type | Set by | Meaning |
|-------|------|--------|---------|
| `coverage_result` | string | Step E.3 | Aggregate percent (e.g. `"82.4"`); empty when skipped |
| `coverage_skip_reason` | string | Step E.3 | Empty when a real number was computed; `"all-main"` when every changed file was `package main` |
| `coverage_tests_generated` | number | Step F | Count of new tests added (0 when Step F didn't run) |

**Caller contract:** When rendering a summary, check `coverage_skip_reason`
before formatting `coverage_result` with a percent sign. If `coverage_skip_reason`
is non-empty, render a textual reason (e.g. `skipped — all changed files are
package main`) instead of `<COV_RESULT>%`.

## Step A: Skip Conditions

Skip this entire workflow (return to the calling command's next step) if ANY of these are true:

- `SKIP_COVERAGE` is `true`
- No source files changed (only tests, docs, configs — see Step B)

## Step B: Detect Changed Source Files

Detect committed/uncommitted/staged/untracked files and filter to source files
per detected project type. For Go, partition into **gated** files (count toward
the aggregate) and **info** files (`package main` — shown in the report but
excluded from the gate).

→ Read `step-b-detect-changed-files.md` for the full procedure: the
`CHANGED_FILES` collector, per-language source-file filters (Go / Node /
Rust / Python), the `get_pkg` comment-aware Go package extractor, and the
gated/info partitioning loop. The rationale for excluding `package main`
(issue #143) lives there.

If `CHANGED_SRC` is empty after filtering → skip (no source files to measure
coverage for). Return to the calling command's next step.

## Step C: Run Coverage

Run the coverage tool appropriate for the detected project type and store
output for analysis.

→ Read `step-c-run-coverage.md` for the per-language commands (Go's built-in
`go test -coverprofile`; Node detection of vitest/jest/c8; Rust llvm-cov or
tarpaulin; Python pytest-cov or coverage.py). It also contains the rule for
when "tool unavailable" should warn-and-skip vs proceed-with-zero-coverage.

If the coverage tool binary is genuinely missing (e.g., `cargo-llvm-cov` not
installed) → display a warning ("Coverage tool unavailable, skipping coverage
gate") and return to the calling command's next step. Otherwise — even if
coverage is 0% — proceed to Step D. **Do NOT treat low coverage as a tool
failure.**

## Step D: Analyze Changed-File Coverage

Parse the coverage output and compute per-file coverage for changed files only:

1. For each file in `CHANGED_SRC`, extract its line or function coverage percentage
2. Identify specific uncovered functions/methods in changed files
3. Calculate the aggregate coverage percentage across changed source files (Go: gated files only — `CHANGED_SRC_GATED`, excluding `package main`; other languages: all of `CHANGED_SRC`)

→ Read `step-d-analyze.md` for the full statement-weighted Go coverprofile
parser (two-pass: gated, then info), the `ALL_MAIN` flag logic, and the
per-language JSON parsing notes (Node coverage-summary.json, Rust
llvm-cov/tarpaulin JSON, Python coverage.json).

**Outputs from Step D** (used by Steps E and F):
- `AGGREGATE_COVERAGE` — percent string (or `"N/A"` when `ALL_MAIN=true`)
- `ALL_MAIN` — boolean: `true` when every changed file is `package main`
- `FILE_REPORT` — per-file table rows (gated rows have empty Notes;
  info rows carry `excluded from gate (package main)`)
- `UNCOVERED_FUNCS` — newline-separated `file:func1, func2` entries
  (Go-only, gated files only — see issue #143)
- `INFO_COUNT` — number of `package main` files included in the report

## Step E: Coverage Gate Decision

**MANDATORY RULE — NO EXCEPTIONS:** When coverage is below `COVERAGE_THRESHOLD`,
your ONLY permitted action is to display the report (Step E.1) and then
IMMEDIATELY call `AskUserQuestion` (Step E.2). You MUST NOT skip, waive,
rationalize, or proceed without asking. **Only the user can decide to proceed
with low coverage.**

**Design philosophy: "if you touch it, you own it."** The entire file's
coverage counts, regardless of which lines you changed. The carve-out for
`package main` (Go only) is detected by the package clause and is the only
exception — see Step B and issue #143.

→ Read `step-e-gate.md` for the full MUST-NOT enumeration, the exact report
formats (Go 4-column with the `ALL_MAIN`-conditional footer; non-Go 3-column),
the gate-decision tree (pass / `ALL_MAIN` warning / coverage < threshold / no
test files / tool failure), every `AskUserQuestion` question + option set
verbatim, the user-choice routing, and the jq blocks that persist
`coverage_result` + `coverage_skip_reason`.

## Step F: Test Generation for Uncovered Code

When the user picks "Generate tests" in Step E.2, generate tests for the
uncovered functions identified in Step D. Three modes (set by the user's
choice):

- **All uncovered functions** (E.2 option 1)
- **Changed functions only** (E.2 option 2, Go only) — diff-driven function
  list intersected with `UNCOVERED_FUNCS`
- **No-test-files path** (Step E.2 "Generate initial tests") — when no test
  files exist anywhere; fall back to extracting exported signatures from
  `CHANGED_SRC` directly

→ Read `step-f-test-generation.md` for: the `CHANGED_FUNC_NAMES` extraction
bash, per-language test-writing conventions (Go table-driven, vitest/jest,
Rust `#[test]`, pytest parametrize), and the `coverage_tests_generated`
state-file write at the end.

## Further Reading

- `step-b-detect-changed-files.md` — `CHANGED_FILES` collector, per-language source filters, `get_pkg` extractor, gated/info partitioning
- `step-c-run-coverage.md` — per-language coverage invocations and JSON shapes
- `step-d-analyze.md` — statement-weighted Go parser, `ALL_MAIN` logic, per-language JSON parsing
- `step-e-gate.md` — report formats, gate decision tree, all `AskUserQuestion` options, state-file persistence
- `step-f-test-generation.md` — mode selection, `CHANGED_FUNC_NAMES` extraction, per-language test generation, final state-file write
