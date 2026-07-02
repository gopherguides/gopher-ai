---
argument-hint: "[path] [--dry-run]"
description: "Find and remove dead Go code, orphaned tests, and complexity issues"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(go:*)", "Bash(git:*)", "Bash(staticcheck:*)", "Bash(deadcode:*)", "Bash(gocyclo:*)", "Bash(gocognit:*)", "Bash(goimports:*)", "Bash(which:*)", "Bash(head:*)", "Bash(echo:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "Agent"]
---

**If `$ARGUMENTS` is empty or not provided:**

Find and clean dead code across the entire Go project.

**Usage:** `/refactor-clean [path] [options]`

**Examples:**

- `/refactor-clean` - Analyze entire project for dead code
- `/refactor-clean ./pkg/...` - Analyze specific package tree
- `/refactor-clean --dry-run` - Report findings without applying fixes
- `/refactor-clean ./internal/auth --dry-run` - Report-only for a specific package

**Analysis categories:** unused exported functions/types, orphaned test files, overly complex functions, unused imports.

**Workflow:** detect tools → parallel-dispatch 4 analysis subagents → present findings report → apply fixes only after user confirmation → verify build + tests.

Set default: `TARGET_PATH="./..."` and proceed.

---

**If `$ARGUMENTS` is provided:**

Parse `$ARGUMENTS`:

- Argument starting with `./` or a package pattern → `TARGET_PATH`
- `--dry-run` → set `DRY_RUN=true`, default `TARGET_PATH="./..."`
- Both: extract path to `TARGET_PATH`, set `DRY_RUN=true`

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "refactor-clean" "COMPLETE"; fi`

## Step 1: Verify Go Project

```bash
if [ ! -f go.mod ]; then
  echo "ERROR: No go.mod found. This command must be run from a Go project root."
  exit 1
fi
head -5 go.mod
```

Capture the module path from `go.mod` for import analysis.

## Step 2: Detect Available Analysis Tools

```bash
echo "=== Tool Detection ==="
which staticcheck 2>/dev/null && staticcheck --version || echo "staticcheck: NOT FOUND"
which deadcode 2>/dev/null || echo "deadcode: NOT FOUND (golang.org/x/tools/cmd/deadcode)"
which gocyclo 2>/dev/null || echo "gocyclo: NOT FOUND"
which gocognit 2>/dev/null || echo "gocognit: NOT FOUND"
which goimports 2>/dev/null || echo "goimports: NOT FOUND"
go version
```

| Tool | Purpose | Fallback |
|------|---------|----------|
| `staticcheck` | Unused code (U1000) | Manual grep for exported symbols with no callers |
| `deadcode` | Unreachable functions | `go vet` + manual export analysis |
| `gocyclo` / `gocognit` | Complexity score | Manual nesting/branch count for funcs >50 lines |
| `goimports` | Unused imports | `go build` error parsing |

If no specialized tools are available, inform the user which would improve results, but proceed regardless.

## Step 3: Parallel Analysis Dispatch

Launch **4 Agent calls in a SINGLE message** (parallel dispatch):

1. **Unused Exports Agent** (sonnet, Explore) — staticcheck `-checks U1000` if available, else deadcode, else manual grep. Exclude `main`/`init`, `cmd/` packages, interface implementations, generated files (`*_templ.go`, `*_mock.go`, `*.pb.go`), `vendor/`. Report file/line/symbol/type/confidence.
2. **Orphaned Tests Agent** (sonnet, Explore) — for each `*_test.go`, check that the corresponding source exists and tested functions still exist. Verify via `go list` before flagging test-only directories. Report file/issue/details.
3. **Complexity Agent** (sonnet, Explore) — gocyclo/gocognit `-over 15` if available, or count nesting depth/branches manually for funcs >50 lines. Report file/line/function/score/extraction suggestion.
4. **Import Cleanup Agent** (sonnet, Explore) — goimports `-l` if available, or parse `go build` output. Flag side-effect imports for review only (do NOT auto-remove).

Each subagent's prompt should include the tools detected in Step 2, `TARGET_PATH`, and the module path. Collect all 4 results, then proceed to Step 4 (present findings).

If a subagent fails or returns empty, fall through to the manual analysis path for that category — see `${CLAUDE_PLUGIN_ROOT}/lib/refactor-clean/manual-analysis.md`.

## Step 4: Present Findings Report

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/refactor-clean/manual-analysis.md` for the full report layout (4 category tables + summary). At a high level, the report has:

- Module path, target path, tools used
- Category A — Unused Code
- Category B — Orphaned Tests
- Category C — Complexity Issues (always manual; never auto-applied)
- Category D — Import Issues (side-effect imports flagged review-only)
- Summary: totals, auto-fixable count, requires-review count

If `--dry-run` was specified: output the report and proceed to completion. Do not ask about applying fixes.

If no findings in any category: report "No dead code or issues found — codebase is clean" and proceed to completion.

## Step 5: Apply Fixes with User Confirmation

**CRITICAL: Never apply fixes without explicit user approval.**

Use `AskUserQuestion`: "I found X issues across Y categories. How would you like to proceed?"

| Option | Description |
|--------|-------------|
| Apply all auto-fixable | Remove unused code, clean imports, remove orphaned tests |
| Apply by category | Choose which categories to fix |
| Apply individually | Confirm each change one by one |
| Skip fixes | Keep the report only |

Complexity suggestions (Category C) always require manual refactoring — provide guidance, never auto-apply.

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

## Step 6: Complexity Refactoring Guidance (Category C)

For each function in Category C:

1. Read the function body and identify extractable logic blocks
2. Suggest concrete function signatures for extracted code
3. Describe the before/after structure

Ask the user if they want any specific complexity refactoring applied. If yes, apply it and verify compilation + tests.

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. All four categories scanned (unused, orphans, complexity, imports)
2. Findings report presented to the user
3. If `--dry-run`: no fixes attempted (report only)
4. If fixes applied: user confirmed each batch
5. If fixes applied: `go build ./...` zero errors
6. If fixes applied: `go test ./...` passes
7. If no findings: user informed that the codebase is clean

```
<done>COMPLETE</done>
```

**Safety note:** If 15+ iterations without success, document blockers and ask the user.

## Further Reading

- `${CLAUDE_PLUGIN_ROOT}/lib/refactor-clean/manual-analysis.md` — full manual analysis fallbacks (staticcheck/deadcode/gocyclo/goimports invocations + manual greps), exclusions list (interface implementations, reflection callers, framework registrations), the orphaned-test detection rules, the complexity threshold table, and the structured findings report layout
