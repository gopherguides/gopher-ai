# Step D — Analyze Changed-File Coverage

Loaded by `coverage-verification.md` Step D. Owns the statement-weighted Go
coverprofile parser, the `ALL_MAIN` flag logic, and the per-language JSON
parsing notes.

## Go: statement-weighted parser

Parse the raw coverprofile to compute **statement-weighted** coverage (not
function-average). The coverprofile format is:

```
mode: set
file.go:startLine.startCol,endLine.endCol numStatements hitCount
```

Use statement counts weighted by whether they were hit. The loop runs twice:
first over `CHANGED_SRC_GATED` (counted toward the aggregate), then over
`CHANGED_SRC_INFO` (`package main` files — displayed but excluded from
totals). Per-file row generation, uncovered-function extraction, and the
`N/A (no statements)` short-circuit are identical in both passes; only the
totals accumulation differs. The `Notes` column distinguishes the two: blank
for gated rows, `excluded from gate (package main)` for info rows.

```bash
COVERAGE_FUNC=$(go tool cover -func=.local/state/coverage.out 2>/dev/null)
AGGREGATE_COVERAGE=""
FILE_REPORT=""
UNCOVERED_FUNCS=""
TOTAL_STMTS=0
TOTAL_COVERED=0
INFO_COUNT=0

# Pass 1: gated files — count toward TOTAL_STMTS / TOTAL_COVERED.
for f in $CHANGED_SRC_GATED; do
  FILE_STMTS=$(grep "^${f}:" .local/state/coverage.out 2>/dev/null | awk '{
    split($2, a, " "); stmts=$2; hit=$3
    total+=stmts; if(hit>0) covered+=stmts
  } END {printf "%d %d", total, covered}')
  FILE_TOTAL=$(echo "$FILE_STMTS" | awk '{print $1}')
  FILE_COVERED=$(echo "$FILE_STMTS" | awk '{print $2}')

  if [ "$FILE_TOTAL" -eq 0 ] 2>/dev/null; then
    FILE_REPORT="${FILE_REPORT}\n| ${f} | N/A (no statements) | — |  |"
    continue
  fi

  FILE_COV=$(awk "BEGIN {printf \"%.1f\", ($FILE_COVERED/$FILE_TOTAL)*100}")
  TOTAL_STMTS=$((TOTAL_STMTS + FILE_TOTAL))
  TOTAL_COVERED=$((TOTAL_COVERED + FILE_COVERED))

  FILE_FUNC_LINES=$(echo "$COVERAGE_FUNC" | grep "^${f}:" | grep -v "^total:")
  UNCOV=$(echo "$FILE_FUNC_LINES" | awk '$NF == "0.0%" {print $2}' | paste -sd ", " -)
  UNCOV_DISPLAY="${UNCOV:-—}"
  FILE_REPORT="${FILE_REPORT}\n| ${f} | ${FILE_COV}% | ${UNCOV_DISPLAY} |  |"

  if [ -n "$UNCOV" ]; then
    UNCOVERED_FUNCS="${UNCOVERED_FUNCS}\n${f}:${UNCOV}"
  fi
done

# Pass 2: info files (package main) — display only, do NOT touch totals.
for f in $CHANGED_SRC_INFO; do
  INFO_COUNT=$((INFO_COUNT + 1))
  FILE_STMTS=$(grep "^${f}:" .local/state/coverage.out 2>/dev/null | awk '{
    split($2, a, " "); stmts=$2; hit=$3
    total+=stmts; if(hit>0) covered+=stmts
  } END {printf "%d %d", total, covered}')
  FILE_TOTAL=$(echo "$FILE_STMTS" | awk '{print $1}')
  FILE_COVERED=$(echo "$FILE_STMTS" | awk '{print $2}')

  NOTE="excluded from gate (package main)"

  if [ "$FILE_TOTAL" -eq 0 ] 2>/dev/null; then
    FILE_REPORT="${FILE_REPORT}\n| ${f} | N/A (no statements) | — | ${NOTE} |"
    continue
  fi

  FILE_COV=$(awk "BEGIN {printf \"%.1f\", ($FILE_COVERED/$FILE_TOTAL)*100}")
  FILE_FUNC_LINES=$(echo "$COVERAGE_FUNC" | grep "^${f}:" | grep -v "^total:")
  UNCOV=$(echo "$FILE_FUNC_LINES" | awk '$NF == "0.0%" {print $2}' | paste -sd ", " -)
  UNCOV_DISPLAY="${UNCOV:-—}"
  FILE_REPORT="${FILE_REPORT}\n| ${f} | ${FILE_COV}% | ${UNCOV_DISPLAY} | ${NOTE} |"
done

# Aggregate is computed from gated files only. ALL_MAIN signals "every changed
# file was package main" — Step E.2 emits a warning instead of running the gate.
ALL_MAIN=false
if [ "$TOTAL_STMTS" -gt 0 ]; then
  AGGREGATE_COVERAGE=$(awk "BEGIN {printf \"%.1f\", ($TOTAL_COVERED/$TOTAL_STMTS)*100}")
elif [ -z "$CHANGED_SRC_GATED" ] && [ -n "$CHANGED_SRC_INFO" ]; then
  AGGREGATE_COVERAGE="N/A"
  ALL_MAIN=true
else
  AGGREGATE_COVERAGE="0.0"
fi
```

## Per-language JSON parsing

For **Node/TypeScript**, parse JSON coverage summary — extract `lines.pct`
for each changed file from the JSON output.

For **Rust**, parse the JSON output from llvm-cov or tarpaulin — extract
per-file line coverage.

For **Python**, parse `coverage.json` — extract
`files.<path>.summary.percent_covered` for each changed file.

## Outputs (consumed by Steps E and F)

| Variable | Type | Notes |
|----------|------|-------|
| `AGGREGATE_COVERAGE` | string | `"82.4"`, `"0.0"`, or `"N/A"` |
| `ALL_MAIN` | `true`/`false` | True only when every changed file is `package main` |
| `FILE_REPORT` | string | Pre-rendered table rows (gated first, then info) |
| `UNCOVERED_FUNCS` | newline-separated | `file:func1, func2` entries (Go-only, gated only) |
| `INFO_COUNT` | int | Number of `package main` files in the report |
| `TOTAL_STMTS`, `TOTAL_COVERED` | int | Raw statement counts from gated pass |
