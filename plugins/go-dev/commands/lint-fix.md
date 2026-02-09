---
argument-hint: "[path] [--check]"
description: "Auto-fix Go linting issues with golangci-lint"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Fix all auto-fixable linting issues in the Go project.

**Usage:** `/lint-fix [path] [options]`

**Examples:**

- `/lint-fix` - Fix all linting issues in project
- `/lint-fix ./pkg/...` - Fix issues in specific package
- `/lint-fix --check` - Check without fixing
- `/lint-fix --staged` - Fix only staged files

**Workflow:**

1. Detect golangci-lint configuration
2. Run linters with auto-fix enabled
3. Run gofmt and goimports
4. Report fixed and remaining issues
5. Optionally stage fixed files

Proceed with fixing all linting issues.

---

**If `$ARGUMENTS` is provided:**

Fix linting issues for specified path or options.

## Loop Initialization

Initialize persistent loop to ensure all fixable issues are resolved:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "lint-fix" "COMPLETE"`

## Configuration

Parse arguments:

- **Path**: Package or file to lint (default: `./...`)
- **--check**: Report issues without fixing
- **--staged**: Only lint staged files
- **--fix-unsafe**: Include unsafe fixes

## Steps

### 1. Detect Linting Tools

```bash
# Check for golangci-lint config
ls .golangci.yml .golangci.yaml golangci.yml 2>/dev/null

# Check golangci-lint version
golangci-lint --version 2>/dev/null
```

### 2. Check Current State

```bash
# Count current issues (without fixing)
golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 2>&1 | tail -20
```

### 3. Run Auto-Fix

**Go formatting:**

```bash
# Format all Go files
gofmt -w -s .

# Organize imports
goimports -w .

# Or use gofumpt for stricter formatting
gofumpt -w .
```

**golangci-lint fixes:**

```bash
# Run with auto-fix
golangci-lint run --fix ./...
```

### 4. Staged Files Only

When using `--staged`:

```bash
# Get staged Go files
STAGED=$(git diff --cached --name-only --diff-filter=ACMR | grep '\.go$')

# Format only staged files
echo "$STAGED" | xargs gofmt -w -s
echo "$STAGED" | xargs goimports -w
```

### 5. Common Linter Fixes

| Linter | Auto-fixable | Manual |
|--------|--------------|--------|
| gofmt | All formatting | - |
| goimports | Import ordering | - |
| govet | - | All issues |
| errcheck | - | Missing error checks |
| staticcheck | Some | Most issues |
| gosimple | Some | Code simplifications |
| gocritic | Some | Style issues |

### 6. Handle Unfixable Issues

After auto-fix, report remaining issues:

```text
Remaining Issues (require manual fix)

| File | Line | Linter | Message |
|------|------|--------|---------|
| pkg/api/handler.go | 45 | errcheck | Error return value not checked |
| pkg/db/query.go | 23 | govet | Printf format %d has arg of wrong type |

Suggested fixes:

1. pkg/api/handler.go:45 - Add error handling: if err != nil { return err }
2. pkg/db/query.go:23 - Change %d to %s for string argument
```

### 7. Generate Report

```text
Lint Fix Complete

Fixed Issues:

| Tool | Fixed |
|------|-------|
| gofmt | 12 files |
| goimports | 8 files |
| golangci-lint | 5 issues |

Total: 25 fixes applied

Remaining Issues: 3 (require manual fixes)

Files Modified:
- pkg/api/handler.go
- pkg/db/query.go
- internal/service/auth.go
- ... (more)

Next Steps:

1. Review changes: git diff
2. Fix remaining issues manually
3. Run tests: go test ./...
4. Stage changes: git add -A
```

### 8. Recommended golangci-lint Config

If no config exists, suggest creating `.golangci.yml`:

```yaml
linters:
  enable:
    - errcheck
    - govet
    - staticcheck
    - gosimple
    - gocritic
    - gofmt
    - goimports
    - misspell
    - unconvert

linters-settings:
  gofmt:
    simplify: true
  goimports:
    local-prefixes: github.com/yourorg/yourproject

issues:
  exclude-use-default: false
  max-issues-per-linter: 0
  max-same-issues: 0
```

## Notes

- Always review auto-fixed changes
- Run tests after fixing: `go test ./...`
- Some fixes may change behavior (rare)
- Use `--check` in CI, `--fix` locally

---

## Structured Output (--json)

If `$ARGUMENTS` contains `--json`, strip the flag from other arguments and after completing all steps, output **only** a JSON object (no markdown, no explanation) matching this schema:

```json
{
  "fixes": [
    {"file": "string", "line": 0, "rule": "string", "severity": "string", "fix": "string"}
  ],
  "summary": {"errors": 0, "warnings": 0, "fixed": 0}
}
```

- `fixes`: Array of all fixes applied (file, line number, linter rule, severity, description of fix)
- `summary`: Counts of errors found, warnings found, and total issues fixed

Still apply all fixes as normal, but output JSON to stdout instead of the markdown report.

> **Important:** When using `--json` mode, do NOT emit the `<done>COMPLETE</done>` marker. The JSON output itself signals completion.

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All auto-fixable issues have been resolved
2. `golangci-lint run` returns 0 errors (or only unfixable issues)
3. Code still compiles (`go build ./...`)
4. Tests still pass (`go test ./...`)

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, linting issues may remain.

---

## Structured Output (`--json`)

When `$ARGUMENTS` contains `--json`, output **only** valid JSON matching this schema instead of markdown. Do not include any text outside the JSON object.

```json
{
  "fixes": [
    {
      "file": "string — file path relative to project root",
      "line": "number — line number of the issue",
      "rule": "string — linter rule name (e.g. 'errcheck', 'govet')",
      "severity": "string — 'error', 'warning', or 'info'",
      "fix": "string — description of the fix applied"
    }
  ],
  "summary": {
    "errors": "number — total errors found",
    "warnings": "number — total warnings found",
    "fixed": "number — total issues auto-fixed"
  }
}
```

**Example:**

```json
{
  "fixes": [
    {"file": "pkg/api/handler.go", "line": 45, "rule": "errcheck", "severity": "error", "fix": "Added error check for db.Close()"},
    {"file": "pkg/db/query.go", "line": 23, "rule": "gofmt", "severity": "warning", "fix": "Reformatted function signature"}
  ],
  "summary": {"errors": 1, "warnings": 1, "fixed": 2}
}
```

Strip the `--json` flag from `$ARGUMENTS` before parsing path and options.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
