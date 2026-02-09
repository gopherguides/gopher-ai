# GitHub Agent Skills for Go Code Quality

A collection of [GitHub Agent Skills](https://docs.github.com/en/copilot/customizing-copilot/copilot-extensions/building-copilot-extensions) for Go code quality auditing, powered by [Gopher Guides](https://gopherguides.com) best practices.

## Skills

| Skill | Description |
|-------|-------------|
| [`go-code-audit`](go-code-audit/) | Comprehensive code quality analysis against Go best practices |
| [`go-test-coverage`](go-test-coverage/) | Test coverage gap analysis and recommendations |
| [`go-best-practices`](go-best-practices/) | Gopher Guides coding standards enforcement |
| [`go-lint-audit`](go-lint-audit/) | Extended lint analysis with human-readable explanations |
| [`go-code-review`](go-code-review/) | Automated PR code review with quality scoring |

## Installation

### Per-Repository (recommended for teams)

Copy the `.github/skills/` directory into your repository:

```bash
# From your project root
cp -r path/to/gopher-ai/.github/skills .github/skills
```

### Personal Installation (for individual use)

Install to your personal Copilot skills directory:

```bash
cp -r path/to/gopher-ai/.github/skills/* ~/.copilot/skills/
```

### Via GitHub CLI

```bash
gh repo clone gopherguides/gopher-ai
cp -r gopher-ai/.github/skills your-project/.github/skills
```

## Agentic Workflows

Example agentic workflow templates are available in [`.github/agentic-workflows/`](../agentic-workflows/):

| Workflow | Description |
|----------|-------------|
| [`daily-code-audit.md`](../agentic-workflows/daily-code-audit.md) | Daily code quality report |
| [`pr-quality-gate.md`](../agentic-workflows/pr-quality-gate.md) | Auto-review PRs before merge |
| [`weekly-test-coverage.md`](../agentic-workflows/weekly-test-coverage.md) | Weekly test improvement PRs |

Run workflows with `gh aw`:

```bash
gh aw run daily-code-audit
gh aw run pr-quality-gate
gh aw run weekly-test-coverage
```

## Configuration

### Gopher Guides API (Optional)

For enhanced analysis powered by Gopher Guides training materials, set your API key:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

Get your API key at [gopherguides.com](https://gopherguides.com).

## License

MIT — See [LICENSE](../../LICENSE) for details.

---

*Built by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
