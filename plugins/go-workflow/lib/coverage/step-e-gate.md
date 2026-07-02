# Step E — Coverage Gate Decision

Loaded by `coverage-verification.md` Step E. Owns the report rendering, the
gate-decision tree, every `AskUserQuestion` option set verbatim, and the
state-file persistence.

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
step. Do NOT call `AskUserQuestion`; there is no signal to act on, and
silently passing would hide the fact that no gate ran. Skipping Step E.3 here
would leave the calling skill (e.g. `$ship`) unable to render the correct
summary line.

```
⚠️  Coverage gate skipped: all changed files are in `package main` (typically bootstrap/wiring code that's untestable in practice). See issue #143 for rationale.
```

### Branch 2 — Coverage >= `COVERAGE_THRESHOLD`

Pass. Run Step E.3 (persist the numeric `coverage_result`), then return to
the calling command's next step.

### Branch 3 — Coverage < `COVERAGE_THRESHOLD`

You MUST call `AskUserQuestion` with this exact question and options:

> **Question:** "Changed files have {AGGREGATE_COVERAGE}% coverage (threshold: {COVERAGE_THRESHOLD}%). What would you like to do?"

**Options (Go projects):**

1. "Generate tests for all uncovered functions in changed files (excludes `package main`)"
2. "Generate tests only for functions I added or modified (excludes `package main`)"
3. "Proceed without additional tests"
4. "Show me the uncovered functions so I can decide"

**Options (non-Go projects):** Omit options 2 and 4 — changed-function
detection and per-function uncovered listings are only supported for Go (Step
D only populates `UNCOVERED_FUNCS` for Go). Present options 1 and 3 only.

**Scope of test generation (Go path):** Options 1, 2, and 4 only consider
gated files (`CHANGED_SRC_GATED`). Uncovered functions in `package main`
files are shown in the report's row for transparency but `UNCOVERED_FUNCS`
only contains gated entries — Step F never generates tests for `func main()`-style
code. This matches the rationale of issue #143 (main is intentionally
untested).

**Routing the user's choice:**

- Option 1 → proceed to Step F in **all uncovered functions** mode (gated files only)
- Option 2 (Go only) → proceed to Step F in **changed functions only** mode (gated files only)
- Option 3 → run Step E.3, then return to the calling command's next step
- Option 4 (Go only) → display the gated-files `UNCOVERED_FUNCS` list with file locations, then re-ask with options 1-3

### Branch 4 — No test files exist at all

Coverage output is empty or all functions show 0% across the board → you MUST
call `AskUserQuestion` with:

> **Question:** "No test files found for changed packages. Changed files have 0% coverage (threshold: {COVERAGE_THRESHOLD}%). What would you like to do?"

**Options:**

1. "Generate initial tests for changed files"
2. "Proceed without tests"

You MUST NOT decide to skip test generation on your own. Only the user can
make this decision.

### Branch 5 — Coverage tool genuinely failed or unavailable

Warn and proceed ONLY if the tool genuinely failed (non-zero exit code AND no
usable output, or missing binary). If `go test -coverprofile` produced a
`coverage.out` file with content, or if the JSON coverage file exists with
data, the tool did NOT fail — proceed with coverage analysis even if coverage
is 0%.

## Step E.3 — Persist Result

Persist `coverage_result` in the state file. Two fields are written: a numeric
`coverage_result` (when a real aggregate exists) and a `coverage_skip_reason`
that explains why the gate did not run, so callers can render a sensible
summary line without producing `N/A%`-style output.

```bash
TMP="${STATE_FILE}.tmp"
if [ "$ALL_MAIN" = "true" ]; then
  jq --arg reason "all-main" '.coverage_result = "" | .coverage_skip_reason = $reason' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
else
  jq --arg cr "$AGGREGATE_COVERAGE" '.coverage_result = $cr | .coverage_skip_reason = ""' \
    "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
fi
```

**Caller contract:** Callers that render a summary line (e.g. `$ship` Step
13f) must check `coverage_skip_reason` before formatting `coverage_result`
with a percent sign. If `coverage_skip_reason` is non-empty, render a textual
reason (e.g. `skipped — all changed files are package main`) instead of
`<COV_RESULT>%`.
