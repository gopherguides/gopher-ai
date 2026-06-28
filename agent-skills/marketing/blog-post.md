# Automated Go Code Quality with GitHub Agent Skills

Draft destination: digitaldrywood.com

## Working Summary

Gopher AI now ships five reusable Agent Skills that let GitHub Copilot and other
compatible coding agents audit Go projects, review pull requests, explain lint
findings, check Gopher Guides standards, and identify missing tests. The skills
install into `.github/skills/` for a repository or `~/.copilot/skills/` for a
personal setup, and they work with local Go tooling before any hosted API is
configured.

## Draft Post

### Automated Go Code Quality with GitHub Agent Skills

Code review gets expensive when every pull request asks reviewers to catch the
same baseline issues: unchecked errors, missing tests, package stutter,
confusing lint failures, undocumented exported APIs, and concurrency hazards.
Those are exactly the kinds of repeatable checks an agent should help with
before a human reviewer spends attention on product behavior and design.

The Gopher AI Agent Skills package collects common Go quality workflows into
five reusable skills:

| Skill | Use it for |
|-------|------------|
| `go-code-audit` | Project-wide quality analysis against Go best practices |
| `go-code-review` | First-pass PR review with categorized findings and scoring |
| `go-lint-audit` | Lint explanations, categories, and configuration guidance |
| `go-standards-audit` | Gopher Guides standards for documentation, structure, and concurrency |
| `go-test-coverage` | Coverage gaps, missing edge cases, and test recommendations |

Each skill is a folder with a `SKILL.md` file that follows the Agent Skills
specification. Compatible agents load the right skill on demand, so your repo can
carry durable review guidance without making every prompt longer.

### Install in a Repository

For a team repository, install the package into `.github/skills/`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```

The installer copies:

- skills to `.github/skills/<skill-name>/`
- helper scripts to `.github/skills/scripts/`
- severity configuration to `.github/skills/config/`
- workflow templates to `.github/agentic-workflows/`

Commit those files so every contributor's compatible agent can discover the
same skills.

```bash
git add .github/skills .github/agentic-workflows
git commit -m "feat: add Gopher AI agent skills"
```

### Install for Yourself

For personal use across repositories:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --personal
```

That installs the skills under `~/.copilot/skills/`.

### Demo: Audit a Go Project

After installation, ask Copilot or another compatible coding agent:

```text
Audit this Go project for code quality issues.
```

The `go-code-audit` skill guides the agent through local checks such as:

```bash
go vet ./...
staticcheck ./...
golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 ./...
```

It then looks beyond tool output for review patterns such as package stutter,
unclear exported APIs, weak error context, unbounded goroutines, and global
mutable state.

TODO: Add screenshot of an audit report showing critical, warning, and
suggestion sections.

### Demo: Review a Pull Request

For PRs, ask:

```text
Review my changes before I open a pull request.
```

The `go-code-review` skill focuses on the diff, runs checks against changed Go
packages, flags breaking API changes, and produces a reviewer-friendly summary.
The goal is not to replace human review. The goal is to move predictable
findings earlier so humans can focus on correctness, product behavior, and
maintainability.

TODO: Add screenshot of a PR review comment or local review summary.

### Demo: Improve Test Coverage

Ask:

```text
What tests am I missing?
```

The `go-test-coverage` skill runs coverage analysis, identifies untested
exported functions and error paths, and recommends table-driven tests that fit
the codebase.

You can also run the helper script directly:

```bash
bash .github/skills/scripts/coverage-report.sh
```

### Customize Severity for Your Team

Teams do not all gate on the same rules. After installation, edit:

```text
.github/skills/config/severity.yaml
```

For example, you might make formatting and data races critical while treating
preallocation hints as suggestions:

```yaml
overrides:
  gofmt: critical
  race: critical
  prealloc: suggestion
```

Coverage thresholds live in the same file.

### CI/CD Integration

Agent Skills are useful interactively, but the same package also supports
automation. A GitHub Actions workflow can call the helper scripts directly:

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
        run: bash .github/skills/scripts/audit.sh . --yes
      - name: Coverage report
        run: bash .github/skills/scripts/coverage-report.sh
```

If you have a Gopher Guides API key, add it as a repository secret and pass it to
the audit step:

```bash
gh secret set GOPHER_GUIDES_API_KEY --body "your-key-here"
```

```yaml
env:
  GOPHER_GUIDES_API_KEY: ${{ secrets.GOPHER_GUIDES_API_KEY }}
```

The API is optional. The skills and scripts still run with local tooling only.
When the API key is set, enhanced analysis can send source code or diffs to
gopherguides.com, so make sure your organization's policy permits external code
analysis.

### Try It on the Demo Repository

The Gopher AI repo includes a small demo project with intentional quality
issues:

```bash
cd agent-skills/examples/demo-repo
make audit SKILLS_SCRIPTS=../../scripts
make coverage SKILLS_SCRIPTS=../../scripts
```

Use it to see the shape of the audit and coverage output before installing the
skills in a production repository.

### Wrap Up

Agent Skills are a practical way to put team standards where coding agents can
find and reuse them. Gopher AI's Go skills make the baseline quality pass
repeatable: audit the project, review the diff, explain lint, enforce standards,
and find missing tests.

Install them from the Gopher AI repository:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```

Then commit `.github/skills/` so the whole team gets the same Go review
baseline.

## Links

- Gopher AI Agent Skills: <https://github.com/gopherguides/gopher-ai/tree/main/agent-skills>
- Setup guide: [`../SETUP.md`](../SETUP.md)
- API reference: [`../../docs/api/README.md`](../../docs/api/README.md)
- Demo repository: [`../examples/demo-repo/`](../examples/demo-repo/)
