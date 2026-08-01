# Step E — Coverage Gate Decision

Loaded by `coverage-verification.md` Step E. Owns the report rendering,
gate-decision tree, test-generation routing, and state-file persistence.

The MANDATORY-RULE block and design rationale ("if you touch it, you own it")
stay in the trunk — they're decision-time content the agent must see before it
even thinks about reading this file.

## Step E.1 — Display Coverage Report

Output ONLY the coverage table and aggregate line. Do NOT add any analysis,
explanation, or commentary. Do NOT discuss why coverage is low or whether the
low coverage is justified.

**Go format** — 4 columns; rows for `package main` files carry a Notes value
of `excluded from gate (package main)`. The footer is selected by the
`ALL_MAIN` flag from Step D — never substitute `{AGGREGATE_COVERAGE}` directly
into the gated-form footer when `ALL_MAIN=true`, or you'll render `N/A%`.

```
## Coverage Report (Changed Files)

| File | Coverage | Uncovered Functions | Notes |
|------|----------|--------------------|-------|
<one row per file from CHANGED_SRC_GATED, then CHANGED_SRC_INFO, using FILE_REPORT from Step D>

# If ALL_MAIN=true:
**Changed-file coverage: N/A — all changed files are `package main`; gate skipped (see Step E.2 warning)**

# Else (ALL_MAIN=false):
**Changed-file coverage: {AGGREGATE_COVERAGE}% (threshold: {COVERAGE_THRESHOLD}%)** [— {INFO_COUNT} file(s) shown for info only]
```

Pick exactly one footer line; do not emit both. The `# If ... # Else` comments
are for this skill's reader — they must not appear in the rendered report.

**Non-Go formats** — keep the existing 3-column table
(`File | Coverage | Uncovered Functions`); the `package main` carve-out is
Go-specific and does not apply to Node/TS, Rust, or Python paths.

## Step E.2 — Gate Decision

Apply IMMEDIATELY after displaying the report — no intervening text or
analysis:

### Branch 1 — Go path, `ALL_MAIN=true`

Every changed file is `package main` → emit this exact one-line warning,
**then run Step E.3 to persist the skip reason** (`coverage_skip_reason =
"all-main"`, `coverage_result = ""`), and return to the calling command's next
step. There is no signal to act on, and
silently passing would hide the fact that no gate ran. Skipping Step E.3 here
would leave the calling skill (e.g. `$go-workflow:ship`) unable to render the correct
summary line.

```
⚠️  Coverage gate skipped: all changed files are in `package main` (typically bootstrap/wiring code that's untestable in practice). See issue #143 for rationale.
```

### Branch 2 — Coverage >= `COVERAGE_THRESHOLD`

Pass. Run Step E.3 (persist the numeric `coverage_result`), then return to
the calling command's next step.

### Branch 3 — Coverage < `COVERAGE_THRESHOLD`

Run Step F in **all uncovered functions** mode. On the Go path, generate only
for gated files (`CHANGED_SRC_GATED`); `package main` entries remain
informational.

After tests are generated and pass, rerun Steps C through E once. If coverage
still misses the threshold, follow Step E.4 with:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=coverage-below-threshold
```

Stop without returning to the calling command's next step and without emitting
its completion marker.

### Branch 4 — No test files exist at all

Coverage output is empty or all functions show 0% across the board → run Step F
in **initial tests** mode, then rerun Steps C through E once. If initial tests
cannot be generated or executed, follow Step E.4 with:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=coverage-no-tests
```

If generated tests run but coverage remains below threshold, use
`WORKFLOW_REASON=coverage-below-threshold`. Stop without returning to the
calling command's next step.

### Branch 5 — Coverage tool genuinely failed or unavailable

If the tool genuinely failed (non-zero exit code AND no usable output, or
missing binary), follow Step E.4 with:

```
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON=coverage-tool-unavailable
```

If `go -C "$WORKTREE_PATH" test -coverprofile=.local/state/coverage.out`
produced a `coverage.out` file with content, or if
the JSON coverage file exists with data, the tool did NOT fail — proceed with
coverage analysis even if coverage is 0%.

## Step E.3 — Persist Result

Persist `coverage_result` in the state file. Two fields are written: a numeric
`coverage_result` (when a real aggregate exists) and a `coverage_skip_reason`
that explains why the gate did not run, so callers can render a sensible
summary line without producing `N/A%`-style output.

```bash
if [ "$ALL_MAIN" = "true" ]; then
  set_loop_field "$STATE_FILE" "coverage_result" "" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "coverage_skip_reason" "all-main" "$WORKFLOW_STATE_PATH"
else
  set_loop_field "$STATE_FILE" "coverage_result" "$AGGREGATE_COVERAGE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "coverage_skip_reason" "" "$WORKFLOW_STATE_PATH"
fi
```

**Caller contract:** Callers that render a summary line (e.g. `$go-workflow:ship` Step
13f) must check `coverage_skip_reason` before formatting `coverage_result`
with a percent sign. If `coverage_skip_reason` is non-empty, render a textual
reason (e.g. `skipped — all changed files are package main`) instead of
`<COV_RESULT>%`.

## Step E.4 — Persist Incomplete Outcome

Set `WORKFLOW_REASON` to the branch-specific reason before running:

```bash
WORKFLOW_RESULT=INCOMPLETE
WORKFLOW_REASON="${WORKFLOW_REASON:?workflow reason is required}"
set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
```

Return `WORKFLOW_RESULT=INCOMPLETE` and `WORKFLOW_REASON=$WORKFLOW_REASON` to
the calling workflow, which owns terminal-promise selection and marker output.
Stop coverage processing and never emit any completion marker from this shared
component.
