# Agent Skills Marketing Materials

Draft distribution materials for the Gopher AI Agent Skills package.

These files are source material for external publishing. They should stay aligned
with the canonical Agent Skills implementation in [`../`](../), especially the
five skills under [`../skills/`](../skills/), the install script at
[`../scripts/install.sh`](../scripts/install.sh), and the `.github/skills/`
install target used by consuming repositories.

## Materials

| File | Purpose |
|------|---------|
| [`awesome-copilot-submission.md`](awesome-copilot-submission.md) | Submission brief and PR body draft for `github/awesome-copilot` |
| [`blog-post.md`](blog-post.md) | Draft blog post for digitaldrywood.com |
| [`youtube-outline.md`](youtube-outline.md) | 12-15 minute screen recording and talking-head outline |

## Current Product Positioning

Gopher AI Agent Skills give Go teams reusable, agent-discoverable code quality
workflows:

- `go-code-audit` for project-wide quality analysis
- `go-code-review` for first-pass PR review
- `go-lint-audit` for lint findings and configuration guidance
- `go-standards-audit` for Gopher Guides standards checks
- `go-test-coverage` for coverage gaps and test recommendations

The local toolchain path works without a Gopher Guides API key. Setting
`GOPHER_GUIDES_API_KEY` enables enhanced analysis powered by Gopher Guides
training materials and should be disclosed anywhere external services are
discussed.
