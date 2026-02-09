---
name: pr-quality-gate
description: Automatically review PRs for Go code quality before merge
trigger: pull_request
skills:
  - go-code-review
  - go-lint-audit
  - go-test-coverage
---

# PR Quality Gate

Automatically review every PR for code quality, test coverage, and Go best practices.

## Steps

1. **Get the PR diff** — `gh pr diff`
2. **Run code review** using the `go-code-review` skill
   - Generate inline comments on issues
   - Calculate quality score
   - Detect breaking API changes
3. **Run lint audit** using the `go-lint-audit` skill on changed files only
4. **Check test coverage** using the `go-test-coverage` skill
   - Verify new code has tests
   - Flag coverage regressions
5. **Post review** as a PR comment with:
   - Quality score
   - Categorized findings
   - Breaking change warnings
   - Test coverage delta
6. **Set status** — Approve if score ≥ 80, request changes if critical issues found

## Gate Criteria

| Check | Required |
|-------|----------|
| Quality Score | ≥ 80/100 |
| Critical Issues | 0 |
| Tests for new code | Yes |
| Coverage regression | < 5% drop |
| Breaking changes | Documented |

## Configuration

Set `GOPHER_GUIDES_API_KEY` for enhanced review powered by Gopher Guides training materials.
