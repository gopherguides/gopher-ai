# Step C — Run Coverage

Loaded by `coverage-verification.md` Step C. Per-language coverage tool
invocations and the rule for distinguishing tool-failure (warn-and-skip) from
zero-coverage (continue to Step D).

## Go (built-in — always available)

```bash
go test -coverprofile=.local/state/coverage.out ./... 2>/dev/null || true
go tool cover -func=.local/state/coverage.out 2>/dev/null
```

Then extract coverage for changed files specifically:

```bash
for f in $CHANGED_SRC; do
  grep "^${f}:" .local/state/coverage.out 2>/dev/null
done
```

Parse the `go tool cover -func` output — each line shows
`file:line: functionName  coverage%`. Extract functions with 0% or low
coverage in changed files.

## Node/TypeScript

```bash
if grep -q '"vitest"' package.json 2>/dev/null; then
  npx vitest run --coverage --coverage.reporter=json-summary 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
elif grep -q '"jest"' package.json 2>/dev/null; then
  npx jest --coverage --coverageReporters=json-summary 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
elif grep -q '"c8"' package.json 2>/dev/null || grep -q '"nyc"' package.json 2>/dev/null; then
  npx c8 --reporter=json-summary npm test 2>/dev/null || true
  COVERAGE_JSON="coverage/coverage-summary.json"
fi
```

Parse `coverage-summary.json` for per-file coverage. Vitest, jest, and c8
(with `json-summary` reporter) all use this format:

```json
{
  "path/to/file.ts": { "lines": { "total": 100, "covered": 75, "pct": 75.0 }, ... },
  "total": { "lines": { "total": 500, "covered": 350, "pct": 70.0 }, ... }
}
```

Extract `lines.pct` for each changed file to compute per-file and aggregate
coverage.

## Rust

```bash
if command -v cargo-llvm-cov >/dev/null 2>&1; then
  cargo llvm-cov --json > .local/state/coverage.json 2>/dev/null || true
elif command -v cargo-tarpaulin >/dev/null 2>&1; then
  cargo tarpaulin --out Json --output-dir .local/state 2>/dev/null || true
fi
```

## Python

```bash
if command -v pytest >/dev/null 2>&1 && python3 -c "import pytest_cov" 2>/dev/null; then
  pytest --cov --cov-report=json:.local/state/coverage.json 2>/dev/null || true
elif command -v coverage >/dev/null 2>&1; then
  coverage run -m pytest 2>/dev/null && coverage json -o .local/state/coverage.json 2>/dev/null || true
fi
```

## Tool-unavailable vs zero-coverage

If the coverage tool binary is genuinely missing (e.g., `cargo-llvm-cov` not
installed) → display a warning ("Coverage tool unavailable, skipping coverage
gate") and return to the calling command's next step.

However, if the coverage command ran and produced output (e.g., `coverage.out`
exists with content, or JSON file exists with data), the tool did NOT fail —
proceed to Step D even if coverage is 0%. **Do NOT treat low coverage as a tool
failure.**
