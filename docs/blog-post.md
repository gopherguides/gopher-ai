# Automated Go Code Quality with GitHub Agent Skills

*Draft blog post for digitaldrywood.com*

---

**TL;DR:** We built a set of GitHub Agent Skills that automatically audit Go code quality, review PRs, analyze test coverage, and enforce best practices — all powered by Gopher Guides training materials. Here's how to set it up in 5 minutes.

---

## What Are Agent Skills?

GitHub Agent Skills are markdown files that teach AI coding assistants (Copilot, Claude Code, etc.) specialized behaviors. Drop a `SKILL.md` file into `.github/skills/` in your repo, and the AI automatically knows how to perform that task.

Think of them as runbooks for AI — instead of explaining to Copilot "here's how we audit Go code at our company" every time, you write it once and it's always available.

## What Are Agentic Workflows?

Agentic Workflows take this further. They're automated tasks that run on a schedule or trigger — like a daily code audit, automatic PR review, or weekly test coverage report. Set them up with `gh aw` and they run themselves.

## The Gopher AI Skills

We created 5 agent skills specifically for Go code quality:

### 1. `go-code-audit` — Full Project Audit

Analyzes your entire codebase for code smells, anti-patterns, and non-idiomatic Go. Checks everything from error handling to package structure to concurrency patterns.

Output is a categorized report with quality score:

```
## Code Audit Report
- 🔴 Critical: 2 (unchecked errors, data race potential)
- 🟡 Warning: 5 (naming conventions, missing godoc)
- 🟢 Suggestion: 8 (style improvements)
- Quality Score: 72/100
```

### 2. `go-code-review` — PR Review

Automated first-pass review on every PR. Runs static analysis on changed files, checks for breaking API changes, and produces inline comments with a quality score.

### 3. `go-test-coverage` — Coverage Analysis

Finds untested code, generates test stubs, and tracks coverage trends. Goes beyond `go test -cover` by identifying specific missing test cases.

### 4. `go-lint-audit` — Smart Linting

Wraps `golangci-lint` with human-readable explanations. Instead of cryptic lint output, you get plain-language descriptions of what's wrong, why it matters, and how to fix it.

### 5. `go-best-practices` — Standards Enforcement

Validates your project against Gopher Guides coding standards: documentation completeness, concurrency patterns, dependency management, and project structure.

## Setting It Up

### Step 1: Install the skills

```bash
# One-liner for your repo
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/.github/skills/scripts/install.sh | bash -s -- --repo .
```

This copies the skills into `.github/skills/` and the agentic workflow templates into `.github/agentic-workflows/`.

### Step 2: Configure severity levels

Edit `.github/skills/config/severity.yaml` to match your team's standards:

```yaml
overrides:
  gofmt: critical          # Hard gate on formatting
  funlen: critical         # Enforce short functions

coverage:
  minimum: 80
```

### Step 3: Set up agentic workflows

```bash
gh extension install github/gh-aw
gh aw run daily-code-audit
```

### Step 4 (optional): Add API key

For enhanced analysis powered by Gopher Guides training materials:

```bash
export GOPHER_GUIDES_API_KEY="your-key"
```

## Real Examples

Here's what the skills catch in practice:

### Before: Unchecked error

```go
os.Remove(tempFile)
```

### After: Proper error handling

```go
if err := os.Remove(tempFile); err != nil {
    return fmt.Errorf("failed to remove temp file %s: %w", tempFile, err)
}
```

<!-- TODO: Add screenshot of audit report -->
<!-- TODO: Add screenshot of PR review comment -->

### Before: Missing context propagation

```go
func ProcessOrder(id string) error {
    // Long-running operation with no context
}
```

### After: Context-aware

```go
func ProcessOrder(ctx context.Context, id string) error {
    // Respects cancellation and timeouts
}
```

## CI/CD Integration

Add to your GitHub Actions workflow:

```yaml
- name: Code Quality Audit
  run: bash .github/skills/scripts/audit.sh
  env:
    GOPHER_GUIDES_API_KEY: ${{ secrets.GOPHER_GUIDES_API_KEY }}
```

The audit script runs `go vet`, `staticcheck`, `golangci-lint`, and optionally the Gopher Guides API — all in one pass.

## Try It

1. **Demo repo:** Clone the [example project](https://github.com/gopherguides/gopher-ai/tree/main/examples/demo-repo) with intentional issues
2. **Install skills:** Run the one-liner installer
3. **Run an audit:** `make audit` or ask Copilot to "audit this code"

Full setup guide: [SETUP.md](https://github.com/gopherguides/gopher-ai/blob/main/.github/skills/SETUP.md)

API documentation: [docs/api/README.md](https://github.com/gopherguides/gopher-ai/blob/main/docs/api/README.md)

---

*Built by [Gopher Guides](https://gopherguides.com) — the official Go training partner. Get your API key at [gopherguides.com](https://gopherguides.com).*
