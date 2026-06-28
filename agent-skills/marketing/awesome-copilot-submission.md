# awesome-copilot Submission Draft

Target repository: <https://github.com/github/awesome-copilot>

## Submission Type

Submit the Gopher AI Go quality checks as Agent Skills under the upstream
`skills/` directory. The current upstream flow expects each skill to live in
`skills/<skill-name>/SKILL.md`, with frontmatter where `name` matches the folder
name and `description` is non-empty.

The five Gopher AI skills already follow that model in this repository:

| Skill | Source | Description |
|-------|--------|-------------|
| `go-code-audit` | [`../skills/go-code-audit/SKILL.md`](../skills/go-code-audit/SKILL.md) | Comprehensive code quality analysis against Go best practices |
| `go-code-review` | [`../skills/go-code-review/SKILL.md`](../skills/go-code-review/SKILL.md) | Automated first-pass PR code review with quality scoring |
| `go-lint-audit` | [`../skills/go-lint-audit/SKILL.md`](../skills/go-lint-audit/SKILL.md) | Extended lint analysis with human-readable explanations |
| `go-standards-audit` | [`../skills/go-standards-audit/SKILL.md`](../skills/go-standards-audit/SKILL.md) | Gopher Guides coding standards enforcement |
| `go-test-coverage` | [`../skills/go-test-coverage/SKILL.md`](../skills/go-test-coverage/SKILL.md) | Test coverage gap analysis and recommendations |

## Upstream Prep Checklist

- Fork `github/awesome-copilot` and create a branch from `main`.
- Run `npm install` in the fork.
- Create each skill folder with `npm run skill:create -- --name <skill-name> --description "<description>"` or copy the prepared folder and verify the frontmatter.
- Keep each skill self-contained for awesome-copilot. If helper scripts or config are included, place them inside that skill folder or replace shared-path references with links to this repository's installer.
- Disclose that `GOPHER_GUIDES_API_KEY` is optional and that API-enhanced analysis sends code or diffs to gopherguides.com.
- Run `npm run skill:validate`.
- Run `npm start` so the upstream README tables are regenerated.
- Test the submitted skills with GitHub Copilot before opening the PR.

## Proposed PR Title

Add Gopher AI Go code quality agent skills

If an AI agent opens the PR, append the AI-agent marker requested by the current
upstream contribution guide.

## Proposed PR Body

````markdown
## Description

Adds five Gopher AI Agent Skills for Go code quality workflows:

- `go-code-audit` for project-wide quality analysis against Go best practices
- `go-code-review` for first-pass PR review with quality scoring
- `go-lint-audit` for lint explanations and `.golangci.yml` recommendations
- `go-standards-audit` for Gopher Guides coding standards checks
- `go-test-coverage` for coverage gap analysis and test recommendations

These skills are based on the Gopher AI Agent Skills package:
https://github.com/gopherguides/gopher-ai/tree/main/agent-skills

The skills work with local Go tooling by default: `go vet`, `go test`,
`staticcheck`, and `golangci-lint`. Teams can optionally set
`GOPHER_GUIDES_API_KEY` for enhanced analysis from Gopher Guides training
materials. API-enhanced analysis can send code or diff content to
gopherguides.com, so the skill docs call out that teams should confirm their
policy before enabling it.

## Type of Contribution

- [x] New skill file.

## Validation

- [x] I have read and followed the CONTRIBUTING.md guidelines.
- [x] I have read and followed the guidance for submissions involving paid services.
- [x] My contribution adds new skill folders in the `skills/` directory.
- [x] The files follow the required naming convention.
- [x] The content is clearly structured and follows the example format.
- [x] I have tested the skills with GitHub Copilot.
- [x] I have run `npm run skill:validate`.
- [x] I have run `npm start` and verified `README.md` is up to date.
- [x] I am targeting the `main` branch for this pull request.

## Additional Notes

Gopher AI also ships an installer for teams that want all five skills, helper
scripts, severity configuration, and agentic workflow templates in one command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
```
````

## Alternate Distribution Path

If upstream maintainers prefer a single installable package instead of five
direct skill entries, use the external plugin review workflow rather than
opening a PR that edits `plugins/external.json` directly. The Gopher AI repo is
public, MIT licensed, and already contains platform plugin manifests under
`plugins/<name>/`, but the Agent Skills package itself is documented under
[`../`](../).
