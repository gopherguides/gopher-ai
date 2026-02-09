# awesome-copilot Submission

> PR template for submitting to [github/awesome-copilot](https://github.com/github/awesome-copilot)

## PR Title

Add Gopher AI — Go Code Quality Agent Skills

## PR Body

### What

[Gopher AI](https://github.com/gopherguides/gopher-ai) — A collection of GitHub Agent Skills for Go code quality auditing, powered by [Gopher Guides](https://gopherguides.com) best practices.

### Skills Included

| Skill | Description |
|-------|-------------|
| `go-code-audit` | Comprehensive code quality analysis against Go best practices |
| `go-test-coverage` | Test coverage gap analysis with stub generation |
| `go-best-practices` | Gopher Guides coding standards enforcement |
| `go-lint-audit` | Extended lint analysis with human-readable explanations |
| `go-code-review` | Automated PR code review with quality scoring |

### Features

- 🔍 **5 agent skills** for Go code quality (audit, review, coverage, lint, best practices)
- 📊 **Configurable severity levels** — teams customize what's critical vs suggestion
- 🤖 **3 agentic workflow templates** — daily audit, PR quality gate, weekly coverage
- 🔌 **API integration** — optional Gopher Guides API for enhanced analysis
- 📦 **One-liner installer** — `curl | bash` or per-repo copy
- 📖 **Comprehensive setup guide** with CI/CD integration

### Category

Agent Skills > Development Tools > Go

### List Entry

```markdown
- [Gopher AI](https://github.com/gopherguides/gopher-ai) - Go code quality agent skills: audit, review, coverage, lint, and best practices enforcement. By Gopher Guides.
```

### Installation

```bash
# Per-repo
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/.github/skills/scripts/install.sh | bash -s -- --repo .

# Personal
curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/.github/skills/scripts/install.sh | bash -s -- --personal
```

### Links

- Repository: https://github.com/gopherguides/gopher-ai
- Setup Guide: https://github.com/gopherguides/gopher-ai/blob/main/.github/skills/SETUP.md
- API Docs: https://github.com/gopherguides/gopher-ai/blob/main/docs/api/README.md
- Demo Repo: https://github.com/gopherguides/gopher-ai/tree/main/examples/demo-repo
