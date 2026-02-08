---
argument-hint: "[path] [--dry-run]"
description: "Find and remove dead Go code, orphaned tests, and complexity issues"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Find and clean dead code across the entire Go project.

**Usage:** `/refactor-clean [path] [options]`

**Examples:**

- `/refactor-clean` - Analyze entire project for dead code
- `/refactor-clean ./pkg/...` - Analyze specific package tree
- `/refactor-clean --dry-run` - Report findings without applying fixes
- `/refactor-clean ./internal/auth --dry-run` - Report-only for a specific package

**Analysis Categories:**

1. Unused exported functions and types
2. Orphaned test files (tests for deleted code)
3. Overly complex functions (suggest extraction)
4. Unused imports beyond goimports coverage

**Workflow:**

1. Detect available analysis tools
2. Scan codebase across all categories
3. Present structured findings report
4. Apply fixes only after user confirmation
5. Verify code still compiles and tests pass

Proceed with analyzing the entire project.

---

**If `$ARGUMENTS` is provided:**

Analyze and clean dead code for the specified path or options.

## Loop Initialization

Initialize persistent loop to ensure all confirmed fixes are applied cleanly:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "refactor-clean" "COMPLETE"`

## Configuration

Parse arguments:

- **Path**: Package or directory to analyze (default: `./...`)
- **--dry-run**: Report findings without applying any fixes

## Steps

### 1. Verify Go Project

```bash
if [ ! -f go.mod ]; then
  echo "ERROR: No go.mod found. This command must be run from a Go project root."
  exit 1
fi
head -5 go.mod
```

Capture the module path from `go.mod` for import analysis.

### 2. Detect Available Analysis Tools

Check for each tool and record availability. The command works with or without any individual tool — missing tools trigger fallback to manual analysis.

```bash
echo "=== Tool Detection ==="
which staticcheck 2>/dev/null && staticcheck --version || echo "staticcheck: NOT FOUND"
which deadcode 2>/dev/null || echo "deadcode: NOT FOUND (golang.org/x/tools/cmd/deadcode)"
which gocyclo 2>/dev/null || echo "gocyclo: NOT FOUND"
which gocognit 2>/dev/null || echo "gocognit: NOT FOUND"
which goimports 2>/dev/null || echo "goimports: NOT FOUND"
go version
```

**Tool usage plan:**

| Tool | Purpose | Fallback if missing |
|------|---------|-------------------|
| `staticcheck` | Unused code detection (U1000) | Manual grep for exported symbols with no callers |
| `deadcode` | Unreachable function detection | `go vet` + manual export analysis |
| `gocyclo` or `gocognit` | Complexity scoring | Count branches manually (if/switch/for nesting depth) |
| `goimports` | Unused import cleanup | `go build` error parsing for unused imports |

If no specialized tools are available, inform the user which tools would improve results and offer to install them, but proceed with manual analysis regardless.

### 3. Analyze Unused Exported Functions and Types

**With staticcheck:**

```bash
staticcheck -checks U1000 ./... 2>&1
```

**With deadcode (more thorough for reachability):**

```bash
deadcode ./... 2>&1
```

**Manual fallback (no tools):**

1. List all exported functions and types:
```bash
grep -rn '^func [A-Z]' --include='*.go' --exclude='*_test.go' .
grep -rn '^type [A-Z]' --include='*.go' --exclude='*_test.go' .
```

2. For each exported symbol, search for references outside its defining file:
```bash
grep -rn 'SymbolName' --include='*.go' . | grep -v 'func SymbolName'
```

3. Symbols with zero external references (excluding the definition and test files) are candidates for removal or unexport.

**Exclusions — do NOT flag these as dead code:**

- `main()` and `init()` functions (entry points)
- Functions in `cmd/` packages (CLI entry points)
- Functions implementing interfaces (check interface satisfaction)
- Functions called via reflection (warn about false positives)
- Functions in generated files (`*_templ.go`, `*_mock.go`, `*.pb.go`, `*_gen.go`)
- Functions registered as HTTP handlers, gRPC services, or similar frameworks
- Functions in `vendor/` directory

### 4. Find Orphaned Test Files

Look for test files whose corresponding source files no longer exist or whose test targets have been removed.

```bash
find . -name '*_test.go' -not -path './vendor/*' -not -path './.git/*' | sort
```

For each `*_test.go` file:

1. Check if corresponding source files exist in the same package directory
2. Extract tested function names:
```bash
grep -oE 'func Test[A-Za-z0-9_]+' path/to/file_test.go | sed 's/func Test//'
```
3. Verify each tested function exists in the package source:
```bash
grep -rn 'func.*FunctionName' --include='*.go' --exclude='*_test.go' path/to/package/
```

**Orphan indicators:**

- Test functions reference functions that no longer exist in the package
- Test file imports packages that no longer exist in `go.mod`
- Directory contains only `*_test.go` files AND `go list` fails on it (distinguishes broken tests from valid test-only packages like integration/blackbox tests)

**Note:** Do NOT flag test-only directories as orphaned without verifying via `go list`. Directories containing only `*_test.go` files are valid if they form a standalone test package (e.g., `package foo_test` for blackbox testing). Use:
```bash
go list ./path/to/testdir 2>&1
```
If `go list` succeeds, the test package is valid even without non-test source files.

### 5. Identify Overly Complex Functions

**With gocyclo:**

```bash
gocyclo -over 15 . 2>&1
```

**With gocognit:**

```bash
gocognit -over 15 . 2>&1
```

**Manual fallback:**

For functions over 50 lines, read and assess:
- Nested if/else depth > 3
- Switch statements with > 10 cases
- Multiple return paths (> 5)
- Function length > 80 lines

**Complexity thresholds:**

| Score | Assessment | Action |
|-------|-----------|--------|
| < 10 | Simple | No action |
| 10-15 | Moderate | Note for awareness |
| 15-25 | Complex | Suggest extraction |
| > 25 | Very complex | Strongly recommend refactoring |

For complex functions, suggest specific extraction points:
- Independent logic blocks that could become helper functions
- Repeated patterns that could be consolidated
- Early returns that simplify remaining logic

### 6. Clean Up Unused Imports

**With goimports:**

```bash
goimports -l . 2>&1
```

**Via go build (catches what goimports misses):**

```bash
go build ./... 2>&1 | grep 'imported and not used'
```

**Beyond standard unused imports — identify unnecessary dependencies:**

- Packages imported solely for side effects (`_ "pkg"`) where the side effect may no longer be needed
- Dependency packages that could be replaced with standard library

**CRITICAL: Do NOT automatically remove side-effect imports (`_ "pkg/..."`).** These require human judgment. Flag them for review but exclude them from automatic cleanup.

### 7. Present Findings Report

Compile all findings into a structured report. Present this to the user BEFORE making any changes.

```text
=== Refactor Clean Report ===

Module: <module-path>
Path analyzed: <target-path>
Tools used: <list of available tools>

--- Category A: Unused Code (X findings) ---

| # | File | Line | Symbol | Type | Confidence |
|---|------|------|--------|------|------------|
| 1 | pkg/auth/token.go | 45 | GenerateOldToken | func | High |
| 2 | internal/db/types.go | 12 | LegacyConfig | type | Medium |

--- Category B: Orphaned Tests (X findings) ---

| # | Test File | Issue | Details |
|---|-----------|-------|---------|
| 1 | pkg/old/handler_test.go | Source file deleted | pkg/old/handler.go missing |
| 2 | internal/v1/api_test.go | Function removed | TestProcessV1Request tests missing func |

--- Category C: Complexity Issues (X findings) ---

| # | File | Line | Function | Score | Suggestion |
|---|------|------|----------|-------|------------|
| 1 | pkg/api/handler.go | 89 | ProcessRequest | 22 | Extract validation logic |
| 2 | internal/engine/run.go | 34 | Execute | 18 | Split into setup/run/cleanup |

--- Category D: Import Issues (X findings) ---

| # | File | Import | Issue |
|---|------|--------|-------|
| 1 | pkg/utils/helper.go | "encoding/xml" | Imported but not used |
| 2 | cmd/server/main.go | _ "net/http/pprof" | Side-effect import (review only) |

--- Summary ---
Total findings: X
  Auto-fixable: Y (unused code removal, import cleanup)
  Requires review: Z (complexity refactoring, side-effect imports)
```

**If `--dry-run` was specified:** Output the report and proceed directly to completion. Do not ask about applying fixes.

**If no findings in any category:** Report "No dead code or issues found — codebase is clean" and proceed to completion.

### 8. Apply Fixes with User Confirmation

**CRITICAL: Never apply fixes without explicit user approval.**

Use AskUserQuestion to present options:

"I found X issues across Y categories. How would you like to proceed?"

| Option | Description |
|--------|-------------|
| Apply all auto-fixable | Remove unused code, clean imports, remove orphaned tests |
| Apply by category | Choose which categories to fix |
| Apply individually | Confirm each change one by one |
| Skip fixes | Keep the report only |

**Note:** Complexity suggestions (Category C) always require manual refactoring — provide specific guidance but do not auto-apply.

**Apply fixes in this order:**
1. Remove unused imports (least disruptive)
2. Remove unused exported functions/types (may create cascading unused imports)
3. Remove orphaned test files/functions
4. Re-run `goimports` to clean up any newly-unused imports from step 2
5. Verify: `go build ./...`
6. Verify: `go test ./...`

**If compilation or tests fail after a fix**, revert that specific change:
```bash
git checkout -- path/to/file.go
```

Report the revert and continue with remaining fixes.

### 9. Provide Complexity Refactoring Guidance

For each function flagged in Category C:

1. Read the function body and identify extractable logic blocks
2. Suggest concrete function signatures for extracted code
3. Describe the before/after structure

Ask the user if they want any specific complexity refactoring applied. If yes, apply it and verify compilation and tests.

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All four analysis categories have been scanned (unused code, orphaned tests, complexity, imports)
2. Findings report has been presented to the user
3. If `--dry-run`: No fixes were attempted (report only)
4. If fixes were applied: User confirmed each batch of changes
5. If fixes were applied: `go build ./...` succeeds with zero errors
6. If fixes were applied: `go test ./...` passes
7. If no findings: User was informed that the codebase is clean

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, issues may remain unaddressed.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
