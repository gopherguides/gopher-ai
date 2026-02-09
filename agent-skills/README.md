# Agent Skills for Go Code Quality

Distributable [Agent Skills](https://agentskills.io) for Go code quality auditing, powered by [Gopher Guides](https://gopherguides.com) best practices.

These skills follow the [Agent Skills specification](https://agentskills.io/specification) and work with GitHub Copilot, Claude Code, and other compatible agents.

## Skills

| Skill | Description |
|-------|-------------|
| [`go-code-audit`](skills/go-code-audit/) | Comprehensive code quality analysis against Go best practices |
| [`go-test-coverage`](skills/go-test-coverage/) | Test coverage gap analysis and recommendations |
| [`go-standards-audit`](skills/go-standards-audit/) | Gopher Guides coding standards enforcement |
| [`go-lint-audit`](skills/go-lint-audit/) | Extended lint analysis with human-readable explanations |
| [`go-code-review`](skills/go-code-review/) | Automated PR code review with quality scoring |

## Installation

### One-liner (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```

This copies skills to your repo's `.github/skills/` directory where agents discover them automatically.

### Per-Repository (manual)

```bash
git clone https://github.com/gopherguides/gopher-ai /tmp/gopher-ai
cp -r /tmp/gopher-ai/agent-skills/skills/* your-project/.github/skills/
cp -r /tmp/gopher-ai/agent-skills/scripts your-project/.github/skills/scripts
cp -r /tmp/gopher-ai/agent-skills/config your-project/.github/skills/config
```

### Personal Installation

Install to your personal skills directory (works across all repos):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --personal
```

## Helper Scripts

| Script | Description |
|--------|-------------|
| [`audit.sh`](scripts/audit.sh) | Full audit: go vet + staticcheck + golangci-lint + optional API |
| [`coverage-report.sh`](scripts/coverage-report.sh) | Coverage report with gap analysis |
| [`install.sh`](scripts/install.sh) | Install skills to a repo or personal directory |

## Agentic Workflows

Example workflow templates for automated quality checks:

| Workflow | Trigger | Description |
|----------|---------|-------------|
| [`daily-code-audit`](workflows/daily-code-audit.md) | Daily | Full project audit with quality score |
| [`pr-quality-gate`](workflows/pr-quality-gate.md) | PR open/update | Auto-review before merge |
| [`weekly-test-coverage`](workflows/weekly-test-coverage.md) | Weekly | Coverage analysis + improvement PR |

## Configuration

### Gopher Guides API (Optional)

For enhanced analysis powered by Gopher Guides training materials:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

All skills and scripts work without an API key using local tools (go vet, staticcheck, golangci-lint). The API provides additional expert-level analysis when available.

Get your API key at [gopherguides.com](https://gopherguides.com).

### Severity Levels

Customize rule severity in [`config/severity.yaml`](config/severity.yaml). See the [Setup Guide](SETUP.md) for details.

## Documentation

- [Setup Guide](SETUP.md) — Installation, CI/CD, troubleshooting
- [API Reference](../docs/api/README.md) — REST API documentation
- [API Usage](references/api-usage.md) — Quick API examples
- [Demo Repository](examples/demo-repo/) — Sample project with intentional issues

## License

MIT — See [LICENSE](../LICENSE) for details.

---

*Built by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
