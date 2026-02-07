---
argument-hint: "[log-path]"
description: "Auto-detect build system, parse errors, and fix until clean"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Auto-detect the project's build system and fix all build errors.

**Usage:** `/build-fix [log-path]`

**Examples:**

- `/build-fix` - Auto-detect build system and fix errors
- `/build-fix ./tmp/air-combined.log` - Fix errors from a specific log file
- `/build-fix ./build/output.log` - Fix errors from custom log location

**Workflow:**

1. Detect project build system (Air, Go, Node/Vite/Webpack)
2. Locate and parse build error logs
3. Read failing source files and understand errors
4. Apply fixes (minimal, targeted changes)
5. Re-check build until clean

Proceed with auto-detection and fix all build errors.

---

**If `$ARGUMENTS` is provided:**

Fix build errors using the specified log file path or build system.

## Loop Initialization

Initialize persistent loop to ensure all build errors are resolved:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "build-fix" "COMPLETE"`

## Step 1: Detect Build System

If `$ARGUMENTS` is a file path that exists, use it directly as the log source and skip detection.

Otherwise, detect the build system in this order:

### 1a. Air (Go hot-reload)

```bash
ls .air.toml air.toml 2>/dev/null
```

If found, parse `.air.toml` to determine log paths:

```bash
# Extract tmp_dir (default: "tmp")
TMP_DIR=$(grep '^tmp_dir' .air.toml 2>/dev/null | sed 's/.*= *"\(.*\)"/\1/' || echo "tmp")

# Extract build log name from [build] section
BUILD_LOG=$(awk '/^\[build\]/,/^\[/' .air.toml 2>/dev/null | grep '^\s*log\s*=' | sed 's/.*= *"\(.*\)"/\1/' || echo "build-errors.log")
```

**Log path priority** (check in order, use first that exists):
1. `${TMP_DIR}/air-combined.log` -- primary log with compilation + template + SQL errors
2. `${TMP_DIR}/${BUILD_LOG}` -- Air's configured build error log
3. Run `go build ./...` directly if no logs exist

### 1b. Go (standard)

```bash
ls go.mod 2>/dev/null
```

If found (and no Air), run `go build ./...` directly. No persistent log file.

### 1c. Node.js (Vite)

```bash
ls vite.config.ts vite.config.js vite.config.mjs 2>/dev/null
```

### 1d. Node.js (Webpack)

```bash
ls webpack.config.js webpack.config.ts 2>/dev/null
```

### 1e. Node.js (generic build script)

```bash
jq -r '.scripts.build // empty' package.json 2>/dev/null
```

### 1f. General fallback

```bash
ls -lt ./tmp/*.log ./log/*.log ./build/*.log 2>/dev/null | head -5
```

### 1g. No build system detected

If nothing is found, ask the user:
- "No build system detected. What build command should I run, and where are the build logs?"

## Step 2: Get Build Errors

### For Air projects (log file exists):

Read the most recent build output from the log. Air appends to the log, so focus on the end:

```bash
tail -200 ${LOG_PATH}
```

Find the most recent build trigger and extract errors after it.

**Check if the log is stale.** Compare the log's modification time to the most recently changed source file. If source files are newer than the log, run a fresh build instead of parsing stale logs.

### For Air projects (no log / stale log):

Run the Air build pipeline manually:

```bash
# Run pre_cmd steps if present in .air.toml (templ generate, sqlc generate, go mod tidy)
go generate ./...
go mod tidy

# Then build
go build ./... 2>&1
```

### For Go (standard):

```bash
go build ./... 2>&1
```

### For Node.js:

```bash
npm run build 2>&1
```

### Already clean?

If the build produces no errors, report "Build is already clean" and proceed to completion.

## Step 3: Parse and Group Errors

Parse errors from the build output. Common patterns:

| Build System | Error Pattern |
|-------------|---------------|
| Go | `./path/file.go:line:col: message` |
| Templ | `Error in file.templ at line X` |
| sqlc | `sqlc generate: message` |
| TypeScript | `file.ts(line,col): error TSxxxx: message` |
| Vite/Webpack | Various, look for file:line references |

Group errors by file. Identify root-cause errors (fix these first, as they often resolve downstream errors).

## Step 4: Read Failing Files

For each file with errors:

1. Read the file content around the error lines
2. Understand the error in context
3. Identify the root cause

**Generated file detection:** Do NOT edit these directly:
- `*_templ.go` -- fix the source `.templ` file, then run `templ generate`
- Files in `internal/database/sqlc/` or similar sqlc output dirs -- fix the `.sql` file, then run `sqlc generate`
- `*_mock.go` -- fix the interface, then regenerate mocks

**Missing dependency detection:** If the error is `cannot find module providing package X`:
- Run `go mod tidy` or `go get X`
- Do not edit source files for this class of error

## Step 5: Apply Fixes

For each error group (ordered by root cause first):

1. Apply the minimal fix using Edit
2. Preserve existing code style
3. Do not refactor unrelated code
4. If fixing a generated-file source (`.templ`, `.sql`), re-run the generator after editing

**Fix priority:**
1. Missing or unused imports
2. Missing dependencies (`go mod tidy` / `go get`)
3. Type errors and interface mismatches
4. Undefined variables or functions
5. Syntax errors
6. Logic errors flagged by the compiler

## Step 6: Re-check Build

After applying fixes, verify the build:

### Air projects (running):

```bash
# Wait for Air to detect changes and rebuild
sleep 3
tail -100 ${LOG_PATH}
```

### Air projects (not running) / Go standard:

```bash
go build ./... 2>&1
```

### Node.js:

```bash
npm run build 2>&1
```

### If new errors appear:

Return to Step 3. Parse, group, read, fix, re-check.

### Cycle detection:

Track error signatures across iterations. If the same error reappears after being "fixed," try an alternative approach. If stuck after 3 attempts on the same error, ask the user for guidance.

## Notes

- Always read the failing file before attempting a fix
- Fix root-cause errors first to minimize iteration count
- For Air projects, `air-combined.log` is the authoritative source (not `build-errors.log`)
- Some projects have both Go and Node builds -- detect and fix both if present
- After fixing generated-file sources, always re-run the generator before re-checking

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Build system detected (or explicit log path confirmed)
2. All build errors parsed and understood
3. Fixes applied to all failing files
4. Build completes successfully with zero errors:
   - **Air projects:** `air-combined.log` shows clean build OR `go build ./...` exits 0
   - **Go projects:** `go build ./...` exits 0
   - **Node projects:** `npm run build` exits 0
5. No regression errors introduced by fixes

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, build errors may remain.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
