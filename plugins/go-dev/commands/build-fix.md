---
argument-hint: "[log-path]"
description: "Auto-detect build system, parse errors, and fix until clean"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**Usage:** `/build-fix [log-path]`

**Examples:**

- `/build-fix` - Auto-detect build system and fix errors
- `/build-fix ./tmp/air-combined.log` - Fix errors from a specific log file
- `/build-fix ./build/output.log` - Fix errors from custom log location

## Loop Initialization

Initialize persistent loop to ensure all build errors are resolved:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "build-fix" "COMPLETE"`

## Step 1: Detect Build Systems

**Important:** A project may have multiple build systems (e.g., Go backend + Vite frontend). Check ALL of the following independently and collect every detected system. Do not stop after the first match.

If `$ARGUMENTS` is a file path that exists, use it as an additional log source for error parsing. **Still run detection below** so all build systems are known for re-checking in Step 6.

Check each build system:

### 1a. Air (Go hot-reload)

Look for the Air config file:

```bash
if [ -f .air.toml ]; then
  AIR_CONFIG=".air.toml"
elif [ -f air.toml ]; then
  AIR_CONFIG="air.toml"
fi
```

If found, extract `tmp_dir` and the build log name:

```bash
TMP_DIR=$(awk '/^tmp_dir[[:space:]]*=/ { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit }' "$AIR_CONFIG")
TMP_DIR="${TMP_DIR:-tmp}"

BUILD_LOG=$(awk '/^\[build\]/,/^\[/ { if ($0 ~ /^[[:space:]]*log[[:space:]]*=/) { gsub(/.*=[[:space:]]*"|".*/, ""); print; exit } }' "$AIR_CONFIG")
BUILD_LOG="${BUILD_LOG:-build-errors.log}"
```

**Log path priority** (check in order, use first that exists):
1. `${TMP_DIR}/air-combined.log` -- primary combined log (compilation + template + SQL errors)
2. `${TMP_DIR}/${BUILD_LOG}` -- Air's configured build error log
3. Fall through to Go standard build if no logs exist

### 1b. Go (standard)

```bash
[ -f go.mod ]
```

If `go.mod` exists, Go is a detected build system. **Continue checking for Node systems below** -- do not stop here.

### 1c. Node.js

Check for Node build systems (in order of specificity):

```bash
# Vite
ls vite.config.ts vite.config.js vite.config.mjs 2>/dev/null

# Webpack
ls webpack.config.js webpack.config.ts 2>/dev/null

# Generic (package.json with build script)
[ -f package.json ] && jq -e '.scripts.build' package.json >/dev/null 2>&1
```

### 1d. General fallback

If no build system was detected above, check for recent log files:

```bash
ls -lt ./tmp/*.log ./log/*.log ./build/*.log 2>/dev/null | head -5
```

### 1e. Nothing detected

If no build system or log file was found, ask the user:
- "No build system detected. What build command should I run, and where are the build logs?"

## Step 2: Get Build Errors

Run builds for **each detected system** and collect all errors.

### Air projects (log file exists):

Read the most recent build output. Air appends to the log, so focus on the end:

```bash
tail -200 "$LOG_PATH"
```

Find the most recent build trigger and extract errors after it.

**Stale log check:** Compare the log's modification time to the most recently changed source file. If source files are newer than the log, skip the log and run a fresh build instead.

### Air projects (no log / stale log):

Run the Air build pipeline manually:

```bash
go generate ./...
go mod tidy
go build ./... 2>&1
```

### Go (standard):

```bash
go build ./... 2>&1
```

### Node.js:

```bash
npm run build 2>&1
```

### Already clean?

If **all** builds produce no errors, report "Build is already clean" and proceed to completion.

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
- Files in sqlc output directories -- fix the `.sql` file, then run `sqlc generate`
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

## Step 6: Re-check All Builds

After applying fixes, re-run **every detected build system**:

### Air projects (running):

```bash
sleep 3
tail -100 "$LOG_PATH"
```

### Go (Air not running or standard):

```bash
go build ./... 2>&1
```

### Node.js:

```bash
npm run build 2>&1
```

Run all applicable builds. If **any** build still has errors, return to Step 3.

### Cycle detection:

Track error signatures across iterations. If the same error reappears after being "fixed," try an alternative approach. If stuck after 3 attempts on the same error, ask the user for guidance.

## Notes

- Always read the failing file before attempting a fix
- Fix root-cause errors first to minimize iteration count
- For Air projects, `air-combined.log` is the authoritative source (not `build-errors.log`)
- After fixing generated-file sources, always re-run the generator before re-checking

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All project build systems have been detected
2. All build errors parsed and understood
3. Fixes applied to all failing files
4. **Every** detected build completes successfully with zero errors:
   - **Air/Go:** `air-combined.log` shows clean build OR `go build ./...` exits 0
   - **Node:** `npm run build` exits 0
5. No regression errors introduced by fixes

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, build errors may remain.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
