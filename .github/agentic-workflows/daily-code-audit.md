---
name: daily-code-audit
description: Run a daily code quality audit on the Go project and report findings
schedule: daily
skills:
  - go-code-audit
  - go-lint-audit
  - go-best-practices
---

# Daily Code Audit

Run a comprehensive code quality audit and generate a report.

## Steps

1. **Run static analysis** using the `go-code-audit` skill on the entire project
2. **Run lint audit** using the `go-lint-audit` skill for detailed linter findings
3. **Check best practices** using the `go-best-practices` skill for standards compliance
4. **Compare with yesterday** — highlight new issues introduced since last audit
5. **Generate report** with categorized findings (critical/warning/suggestion)
6. **Create issue** if critical findings are detected, or update existing tracking issue

## Expected Output

A markdown report with:
- Quality score trend (today vs previous)
- New issues introduced
- Issues resolved
- Top 3 priority action items
- Package-by-package breakdown

## Configuration

Set `GOPHER_GUIDES_API_KEY` for enhanced analysis powered by Gopher Guides training materials.
