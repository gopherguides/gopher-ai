---
argument-hint: "[path]"
description: "Run full pre-push verification: build, test, lint, vet, dev-server checks"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Run verification on entire project.

**Usage:** `/verify [path]`. `/verify` (entire project), `/verify ./pkg/...`, `/verify ./cmd/server/...`.

**Workflow:** `go vet` → `go build` → `go test` → `golangci-lint` (if available, with auto-fix) → check dev-server logs (Air/Vite) → fix issues automatically where safe, report others → loop until all blocking checks pass.

This is your pre-push sanity check.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "verify" "COMPLETE"; fi`

## Configuration

```bash
TARGET_PATH="${ARGUMENTS:-./...}"
echo "Verifying: $TARGET_PATH"
```

---

## Step 1: go vet (static analysis)

```bash
go vet $TARGET_PATH 2>&1
```

Format: `file.go:line:col: message`. Common: Printf format mismatches, unreachable code, shadowed variables.

If issues found, **non-blocking**: report with file:line refs, attempt obvious fixes (format strings, unreachable code), re-run vet to confirm. Continue regardless.

## Step 2: go build (compilation) — BLOCKING

```bash
go build $TARGET_PATH 2>&1
```

If errors, auto-fix using build-fix patterns:

1. Parse errors by file, group related errors
2. Read failing files for context
3. Identify root cause and apply minimal fixes:
   - Missing imports → add or `go get`
   - Unused imports → remove
   - Type mismatches → fix conversions
   - Missing deps → `go mod tidy`
   - Undefined vars/funcs → check spelling, scope
4. Re-run `go build` until clean

**Generated files — do NOT edit directly:**

- `*_templ.go` → fix the source `.templ`, then `templ generate`
- sqlc output → fix the `.sql`, then `sqlc generate`
- `*_mock.go` → fix the interface, regenerate mocks

**Cycle detection:** track error signatures across iterations. If the same error reappears after a "fix," try an alternative approach. After 5 attempts on the same error, ask the user.

## Step 3: go test (test suite) — BLOCKING

```bash
go test $TARGET_PATH -count=1 2>&1
```

**Do NOT auto-fix test logic.** Test failures indicate real problems requiring human judgment.

If failing, ask via `AskUserQuestion`: "Tests are failing (shown above). Would you like to investigate and fix them?"

| Option | Action |
|--------|--------|
| **Yes, fix tests** | Read test files + code under test, attempt targeted fixes (max 3 attempts before asking again) |
| **No, stop here** | Exit without `<done>COMPLETE</done>` |

## Step 4: golangci-lint (code quality)

```bash
command -v golangci-lint >/dev/null 2>&1 && echo "FOUND" || echo "NOT_FOUND"
```

If not installed, report and skip.

If installed, run with auto-fix:

```bash
golangci-lint run --fix $TARGET_PATH 2>&1
```

If unfixable issues remain → report them (non-blocking). Continue.

## Step 5: Dev-Server Logs (Air, runtime checks)

```bash
if [ -f .air.toml ]; then
  AIR_CONFIG=".air.toml"
elif [ -f air.toml ]; then
  AIR_CONFIG="air.toml"
fi
```

If Air config found, extract log paths:

```bash
TMP_DIR=$(awk '/^tmp_dir[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit }' "$AIR_CONFIG")
TMP_DIR="${TMP_DIR:-tmp}"

BUILD_LOG=$(awk '/^\[build\]/,/^\[/ { if ($0 ~ /^[[:space:]]*log[[:space:]]*=/) { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit } }' "$AIR_CONFIG")
BUILD_LOG="${BUILD_LOG:-build-errors.log}"
```

**Log priority** (use first that exists): `${TMP_DIR}/air-combined.log` (combined: compilation + template + SQL), then `${TMP_DIR}/${BUILD_LOG}`.

**Stale-log guard:** if source files are newer than the log, skip — the log is stale.

If fresh, read tail and parse for: Go compile errors (`file.go:line:col: message`), templ errors, sqlc errors, runtime panics (`panic:` / `fatal error:`). Report non-blocking findings.

If no Air config → skip.

## Step 6: Summary

```
Verification Summary

| Check          | Status                          |
|----------------|---------------------------------|
| go vet         | Passed / Fixed N issues         |
| go build       | Passed                          |
| go test        | Passed (N tests)                |
| golangci-lint  | Passed / N warnings / Skipped   |
| Dev-server logs| Clean / N warnings / Skipped    |

Your code is ready to push!
```

If auto-fixes were applied, list them.

## Notes

- Auto-fixes build errors and lint issues using proven `/build-fix` and `/lint-fix` patterns
- **Blocks on:** build errors, test failures
- **Non-blocking:** vet issues, unfixable lint, dev-server warnings
- Test failures are never auto-fixed without user approval — avoids masking real bugs
- For Air projects, `air-combined.log` is the authoritative log source (not `build-errors.log`)

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. `go vet` ran (issues fixed or reported)
2. `go build $TARGET_PATH` exits 0
3. `go test $TARGET_PATH` exits 0
4. `golangci-lint` ran or skipped (if not installed)
5. Dev-server logs checked or skipped (if no config)

```
<done>COMPLETE</done>
```

**NEVER output if:** build errors remain, tests failing, or 15+ iterations (ask user instead).
