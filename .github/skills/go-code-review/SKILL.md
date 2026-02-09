---
name: go-code-review
description: |
  WHEN: User wants an automated first-pass code review on a PR, diff, or set of changes.
  Also when asked "review this PR", "review my changes", or "what do you think of this code?"
  WHEN NOT: Full project audits (use go-code-audit), or when user just wants linting (use go-lint-audit).
license: MIT
---

# Go Code Review

Automated PR code review for Go projects. Provides first-pass review with inline comments, quality scoring, and breaking change detection.

## What It Does

1. **Analyzes PR diff** for code quality issues
2. **Generates inline comments** on specific lines
3. **Produces a quality score** (0-100)
4. **Flags breaking API changes**
5. **Summarizes findings** with actionable next steps

## Steps

### 0. Verify API Key

Before proceeding, verify your Gopher Guides API key is set and valid:

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

If this fails or `GOPHER_GUIDES_API_KEY` is not set:

1. Get your API key at [gopherguides.com](https://gopherguides.com)
2. Set it in your shell profile:
   ```bash
   export GOPHER_GUIDES_API_KEY="your-key"
   ```
3. Restart your terminal or run the export command

**Do not proceed without a valid API key.**

### 1. Get the Diff

```bash
# For a PR
gh pr diff {number}

# For uncommitted changes
git diff

# For staged changes
git diff --cached

# For changes against main
git diff main...HEAD
```

### 2. Static Analysis on Changed Files

```bash
# Get list of changed Go files
CHANGED=$(git diff --name-only main...HEAD | grep '\.go$')

# Run vet on changed packages
echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go vet

# Run staticcheck on changed packages
echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs staticcheck

# Run tests on affected packages
echo "$CHANGED" | xargs -I{} dirname {} | sort -u | xargs go test -race -count=1
```

### 3. Review Checklist

For each changed file, check:

**Correctness**
- [ ] Error handling on all fallible operations
- [ ] No nil pointer dereferences
- [ ] Proper resource cleanup (defer Close)
- [ ] Context propagation in concurrent code
- [ ] No data races (channels/mutexes used correctly)

**Readability**
- [ ] Clear naming following Go conventions
- [ ] Functions are focused (single responsibility)
- [ ] Comments explain "why", not "what"
- [ ] No magic numbers/strings

**Maintainability**
- [ ] Tests added/updated for changes
- [ ] No dead code introduced
- [ ] Dependencies justified
- [ ] Backward compatibility preserved (or breaking change documented)

**Performance**
- [ ] No unnecessary allocations in hot paths
- [ ] Slices pre-allocated where size is known
- [ ] No unbounded goroutine creation

### 4. Breaking Change Detection

Check for API-breaking changes in exported symbols:

```bash
# Compare exported symbols between main and current branch
# Look for removed/renamed exported functions, types, methods
git diff main...HEAD -- '*.go' | grep -E "^-func [A-Z]|^-type [A-Z]|^-var [A-Z]|^-const [A-Z]"
```

**Breaking changes include:**
- Removed exported functions/types/methods
- Changed function signatures
- Changed struct field types
- Removed interface methods (breaks implementors)
- Changed package paths

### 5. Gopher Guides API Review

When `GOPHER_GUIDES_API_KEY` is available:

**Standard shell:**

```bash
DIFF=$(git diff main...HEAD)
curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"diff\": $(echo "$DIFF" | jq -Rs .)}" \
  https://gopherguides.com/api/gopher-ai/review
```

**Claude Code syntax:**

```
Run: DIFF=$(git diff main...HEAD); curl -s -X POST -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" -H "Content-Type: application/json" -d "{\"diff\": $(echo "$DIFF" | jq -Rs .)}" https://gopherguides.com/api/gopher-ai/review
```

### Severity Configuration

Review findings use severity levels from `.github/skills/config/severity.yaml`. See the [Setup Guide](../SETUP.md) for details.

## Output Format

```markdown
## Code Review Summary

**PR:** #{number} — {title}
**Files Changed:** {count}
**Quality Score:** {score}/100

### 🔴 Must Fix ({n})
Issues that should be addressed before merge.

1. **`file.go:{line}`** — {issue}
   ```go
   // suggestion
   ```

### 🟡 Should Fix ({n})
Issues that improve code quality.

1. **`file.go:{line}`** — {issue}

### 🟢 Nit ({n})
Minor style or preference items.

1. **`file.go:{line}`** — {issue}

### ⚠️ Breaking Changes
{list of breaking API changes, or "None detected"}

### ✅ What Looks Good
{positive feedback on well-written code}

### Tests
- [ ] New tests added for new functionality
- [ ] Existing tests pass
- [ ] Edge cases covered

### Recommendation
**{APPROVE | REQUEST_CHANGES | COMMENT}**
{brief summary of overall assessment}
```

## Quality Score Rubric

| Criteria | Points | Description |
|----------|--------|-------------|
| Error Handling | 20 | All errors checked and wrapped |
| Test Coverage | 20 | New code has tests |
| Naming/Style | 15 | Idiomatic Go conventions |
| Documentation | 15 | Exported symbols documented |
| Complexity | 15 | Functions focused, readable |
| Safety | 15 | No races, leaks, or panics |

## References

- Existing gopher-ai command: `plugins/go-workflow/commands/address-review.md`
- Gopher Guides API: `plugins/gopher-guides/skills/gopher-guides/`
- [Go Code Review Comments](https://github.com/golang/go/wiki/CodeReviewComments)

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
