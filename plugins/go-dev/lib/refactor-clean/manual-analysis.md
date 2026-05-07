# Refactor-Clean — Manual Analysis Fallbacks

Loaded by `commands/refactor-clean.md` Step 3 when a parallel analysis
subagent fails or returns empty (use the matching section as fallback for
that category only). Also serves as the reference for what each subagent
should do.

## Category A: Unused Exported Functions and Types

All commands use `$TARGET_PATH` from the trunk's Configuration step.

**With staticcheck:**

```bash
staticcheck -checks U1000 $TARGET_PATH 2>&1
```

**With deadcode (more thorough for reachability):**

```bash
deadcode $TARGET_PATH 2>&1
```

**Manual fallback (no tools):**

1. List all exported functions, methods, and types (convert package pattern to directory):

```bash
SEARCH_DIR=$(echo "$TARGET_PATH" | sed 's|/\.\.\.$||')
# Exported standalone functions: func ExportedName(...)
grep -rn '^func [A-Z]' --include='*.go' --exclude='*_test.go' "$SEARCH_DIR"
# Exported methods: func (r *Receiver) ExportedName(...) or func (r Receiver) ExportedName(...)
grep -rn '^func ([^)]*) [A-Z]' --include='*.go' --exclude='*_test.go' "$SEARCH_DIR"
# Exported types
grep -rn '^type [A-Z]' --include='*.go' --exclude='*_test.go' "$SEARCH_DIR"
```

2. For each exported symbol, search for references outside its defining file:

```bash
grep -rn 'SymbolName' --include='*.go' . | grep -v 'func SymbolName'
```

3. Symbols with zero external references (excluding the definition and test files) are candidates for removal or unexport.

### Exclusions — do NOT flag these as dead code

- `main()` and `init()` functions (entry points)
- Functions in `cmd/` packages (CLI entry points)
- Functions implementing interfaces (check interface satisfaction)
- Functions called via reflection (warn about false positives)
- Functions in generated files (`*_templ.go`, `*_mock.go`, `*.pb.go`, `*_gen.go`)
- Functions registered as HTTP handlers, gRPC services, or similar frameworks
- Functions in `vendor/`

## Category B: Orphaned Test Files

```bash
SEARCH_DIR=$(echo "$TARGET_PATH" | sed 's|/\.\.\.$||')
find "$SEARCH_DIR" -name '*_test.go' -not -path './vendor/*' -not -path './.git/*' | sort
```

For each `*_test.go`:

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
- Directory contains only `*_test.go` AND `go list` fails on it

**Note:** Do NOT flag test-only directories as orphaned without verifying via `go list`. Directories containing only `*_test.go` are valid if they form a standalone test package (e.g., `package foo_test` for blackbox testing):

```bash
go list ./path/to/testdir 2>&1
```

If `go list` succeeds, the test package is valid even without non-test source files.

## Category C: Overly Complex Functions

**With gocyclo:**

```bash
SEARCH_DIR=$(echo "$TARGET_PATH" | sed 's|/\.\.\.$||')
gocyclo -over 15 "$SEARCH_DIR" 2>&1
```

**With gocognit:**

```bash
SEARCH_DIR=$(echo "$TARGET_PATH" | sed 's|/\.\.\.$||')
gocognit -over 15 "$SEARCH_DIR" 2>&1
```

**Manual fallback** — for functions over 50 lines, assess:

- Nested if/else depth > 3
- Switch statements with > 10 cases
- Multiple return paths (> 5)
- Function length > 80 lines

### Complexity Thresholds

| Score | Assessment | Action |
|-------|-----------|--------|
| < 10 | Simple | No action |
| 10-15 | Moderate | Note for awareness |
| 15-25 | Complex | Suggest extraction |
| > 25 | Very complex | Strongly recommend refactoring |

For complex functions, suggest specific extraction points: independent logic blocks → helper functions; repeated patterns → consolidation; early returns that simplify remaining logic.

## Category D: Unused Imports

**With goimports:**

```bash
SEARCH_DIR=$(echo "$TARGET_PATH" | sed 's|/\.\.\.$||')
goimports -l "$SEARCH_DIR" 2>&1
```

**Via go build (catches what goimports misses):**

```bash
go build $TARGET_PATH 2>&1 | grep 'imported and not used'
```

**Beyond standard unused imports:**

- Packages imported solely for side effects (`_ "pkg"`) where the side effect may no longer be needed
- Dependency packages that could be replaced with stdlib

**CRITICAL: Do NOT automatically remove side-effect imports (`_ "pkg/..."`).** These require human judgment. Flag them for review only.

## Findings Report Layout

```
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
