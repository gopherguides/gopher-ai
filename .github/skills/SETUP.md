# Setup Guide — Gopher AI Agent Skills

Step-by-step guide for installing and configuring Go code quality agent skills for your team.

> **Reference:** [gopherguides/gopher-ai#51](https://github.com/gopherguides/gopher-ai/issues/51)

---

## Prerequisites

| Requirement | Install | Verify |
|---|---|---|
| **Go 1.21+** | [go.dev/dl](https://go.dev/dl/) | `go version` |
| **GitHub CLI** | `brew install gh` | `gh --version` |
| **golangci-lint** | `brew install golangci-lint` | `golangci-lint --version` |
| **staticcheck** | `go install honnef.co/go/tools/cmd/staticcheck@latest` | `staticcheck -version` |
| **GitHub Copilot subscription** | [github.com/features/copilot](https://github.com/features/copilot) | — |
| **Gopher Guides API key** *(optional)* | [gopherguides.com](https://gopherguides.com) | See below |

### Verify API key

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me
```

---

## Installation

### Option A: Per-Repository (recommended for teams)

```bash
cd your-project

# Clone and copy skills
git clone https://github.com/gopherguides/gopher-ai /tmp/gopher-ai
cp -r /tmp/gopher-ai/.github/skills .github/skills

# Or use the install script
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/.github/skills/scripts/install.sh | bash -s -- --repo .
```

Commit the `.github/skills/` directory to your repository. Every contributor with Copilot will automatically get the skills.

### Option B: Personal Installation

Install to your personal Copilot skills directory (works across all your repos):

```bash
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/.github/skills/scripts/install.sh | bash -s -- --personal
```

Or manually:

```bash
git clone https://github.com/gopherguides/gopher-ai /tmp/gopher-ai
mkdir -p ~/.copilot/skills
cp -r /tmp/gopher-ai/.github/skills/* ~/.copilot/skills/
```

### Option C: Claude Code Plugin

```bash
/plugin marketplace add gopherguides/gopher-ai
/plugin install go-dev@gopher-ai
```

---

## Configuring Severity Levels

The file `.github/skills/config/severity.yaml` controls which rules are critical, warning, or suggestion.

### Customize for your team

```bash
# Edit severity config
$EDITOR .github/skills/config/severity.yaml
```

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

Copy the workflow templates to your repo:

```bash
cp -r /tmp/gopher-ai/.github/agentic-workflows .github/agentic-workflows
```

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

### Configure schedule

Edit the workflow files in `.github/agentic-workflows/` to change cron schedules, notification channels, etc.

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
        run: bash .github/skills/scripts/audit.sh
      - name: Coverage check
        run: bash .github/skills/scripts/coverage-report.sh
```

### Setting the API key in CI

```bash
gh secret set GOPHER_GUIDES_API_KEY --body "your-key-here"
```

---

## Using the Skills

Once installed, skills activate automatically in Copilot Chat and Claude Code:

| Trigger | Skill |
|---|---|
| "Audit this code" / "code quality check" | `go-code-audit` |
| "Review this PR" / "review my changes" | `go-code-review` |
| "What tests am I missing?" / "improve coverage" | `go-test-coverage` |
| "Run linting" / "what's wrong with my code?" | `go-lint-audit` |
| "Check best practices" / "is this idiomatic?" | `go-best-practices` |

### With API integration

Set your API key in the environment:

```bash
export GOPHER_GUIDES_API_KEY="your-key-here"
```

Skills will automatically use the Gopher Guides API for enhanced analysis when the key is available.

---

## Troubleshooting

### Skills not showing up in Copilot

1. Verify files are in `.github/skills/` (per-repo) or `~/.copilot/skills/` (personal)
2. Each skill folder must contain a `SKILL.md` with valid YAML frontmatter
3. Restart your editor / Copilot session

### API key not working

```bash
# Test the key
curl -s -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  https://gopherguides.com/api/gopher-ai/me

# Common issues:
# - Key has leading/trailing whitespace
# - Key expired — contact gopherguides.com for renewal
# - Firewall blocking gopherguides.com
```

### golangci-lint errors

```bash
# Update to latest
brew upgrade golangci-lint

# Clear cache
golangci-lint cache clean

# Run with verbose output
golangci-lint run -v ./...
```

### Coverage report fails

```bash
# Ensure tests compile
go test -run=^$ ./...

# Check for build tags
go test -tags=integration -coverprofile=coverage.out ./...
```

### Agentic workflows not running

1. Verify `gh aw` is installed: `gh aw --version`
2. Check workflow files exist in `.github/agentic-workflows/`
3. Ensure GitHub Actions is enabled for the repository
4. Check workflow run logs: `gh run list --workflow=code-quality.yml`

---

## Next Steps

- 📖 [API Documentation](../../docs/api/README.md) — Full API reference
- 🎯 [Severity Configuration](config/severity.yaml) — Customize rule severity
- 📊 [Skills Overview](README.md) — All available skills
- 🏗️ [Demo Repository](../../examples/demo-repo/) — Try skills on sample code

---

*Built by [Gopher Guides](https://gopherguides.com) — the official Go training partner.*
