# Setup Guide — Gopher AI Agent Skills

Step-by-step guide for installing and configuring Go code quality agent skills for your team.

---

## Prerequisites

| Requirement | Install | Verify |
|---|---|---|
| **Go 1.21+** | [go.dev/dl](https://go.dev/dl/) | `go version` |
| **GitHub CLI** | `brew install gh` | `gh --version` |
| **golangci-lint** | `brew install golangci-lint` | `golangci-lint --version` |
| **staticcheck** | `go install honnef.co/go/tools/cmd/staticcheck@latest` | `staticcheck -version` |
| **Gopher Guides API key** *(optional)* | [gopherguides.com](https://gopherguides.com) | See below |

### Verify API key (optional)

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

All skills work without an API key using local tools. The API provides enhanced analysis.

---

## Installation

### Option A: Per-Repository (recommended for teams)

```bash
cd your-project

# Use the install script
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```

Or manually:

```bash
git clone https://github.com/gopherguides/gopher-ai /tmp/gopher-ai
mkdir -p .github/skills
cp -r /tmp/gopher-ai/agent-skills/skills/* .github/skills/
cp -r /tmp/gopher-ai/agent-skills/scripts .github/skills/scripts
cp -r /tmp/gopher-ai/agent-skills/config .github/skills/config
```

Commit the `.github/skills/` directory to your repository. Every contributor with a compatible agent will automatically get the skills.

### Option B: Personal Installation

Install to your personal skills directory (works across all your repos):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --personal
```

### Option C: Claude Code Plugin

For Claude Code users, the existing plugins provide the same functionality plus slash commands:

```bash
/plugin marketplace add gopherguides/gopher-ai
/plugin install go-dev@gopher-ai
/plugin install gopher-guides@gopher-ai
```

---

## Configuring Severity Levels

After installation, edit `.github/skills/config/severity.yaml` to customize which rules are critical, warning, or suggestion.

### Customize for your team

Common overrides:

```yaml
overrides:
  gofmt: critical          # Hard gate on formatting
  funlen: critical         # Enforce short functions
  prealloc: suggestion     # Relax prealloc checks
```

### Coverage thresholds

```yaml
coverage:
  minimum: 80              # Overall project minimum
  per_package_minimum: 60  # Per-package minimum
  below_threshold_severity: warning
```

---

## Setting Up Agentic Workflows

Agentic workflows run skills automatically on a schedule or in response to events.

### Install `gh aw` extension

```bash
gh extension install github/gh-aw
```

### Available workflows

The install script copies workflow templates to `.github/agentic-workflows/`:

| Workflow | Schedule | Description |
|---|---|---|
| `daily-code-audit` | Daily at 9 AM | Full project audit with quality score |
| `pr-quality-gate` | On PR open/update | Auto-review before merge |
| `weekly-test-coverage` | Weekly Monday 9 AM | Coverage analysis + improvement PR |

### Run manually

```bash
gh aw run daily-code-audit
gh aw run pr-quality-gate
gh aw run weekly-test-coverage
```

---

## CI/CD Integration

### GitHub Actions

Add to your workflow (`.github/workflows/code-quality.yml`):

```yaml
name: Code Quality
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - name: Install tools
        run: |
          go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
          go install honnef.co/go/tools/cmd/staticcheck@latest
      - name: Run audit
        env:
          GOPHER_GUIDES_API_KEY: ${{ secrets.GOPHER_GUIDES_API_KEY }}
        run: bash .github/skills/scripts/audit.sh . --yes
      - name: Coverage check
        run: bash .github/skills/scripts/coverage-report.sh
```

### Setting the API key in CI

```bash
gh secret set GOPHER_GUIDES_API_KEY --body "your-key-here"
```

The audit script works without the key (local tools only). Add the secret for API-enhanced analysis.

---

## Using the Skills

Once installed, skills activate automatically in compatible agents:

| Trigger | Skill |
|---|---|
| "Audit this code" / "code quality check" | `go-code-audit` |
| "Review this PR" / "review my changes" | `go-code-review` |
| "What tests am I missing?" / "improve coverage" | `go-test-coverage` |
| "Run linting" / "what's wrong with my code?" | `go-lint-audit` |
| "Check best practices" / "is this idiomatic?" | `go-standards-audit` |

---

## Troubleshooting

### Skills not activating

1. Verify files are in `.github/skills/` (per-repo) or `~/.copilot/skills/` (personal)
2. Each skill folder must contain a `SKILL.md` with valid YAML frontmatter
3. Restart your editor / agent session

### API key not working

```bash
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me

# Common issues:
# - Key has leading/trailing whitespace
# - Key expired — contact gopherguides.com for renewal
# - Firewall blocking gopherguides.com
```

### golangci-lint errors

```bash
brew upgrade golangci-lint
golangci-lint cache clean
golangci-lint run -v ./...
```

### Coverage report fails

```bash
go test -run=^$ ./...
go test -tags=integration -coverprofile=coverage.out ./...
```

---

## Next Steps

- [API Documentation](../docs/api/README.md) — Full API reference
- [Severity Configuration](config/severity.yaml) — Customize rule severity
- [Demo Repository](examples/demo-repo/) — Try skills on sample code

---

*Built by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
