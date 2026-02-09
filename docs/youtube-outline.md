# YouTube Video Outline: Automated Go Code Quality with GitHub Agent Skills

**Target length:** 12-15 minutes
**Style:** Screen recording + talking head

---

## 1. Hook/Intro (0:00–0:45)

- "What if your AI coding assistant automatically knew every Go best practice — error handling, concurrency patterns, project structure — without you having to explain it every time?"
- Quick montage: audit report, PR review comment, coverage gap found
- "Today I'll show you how to set this up in under 5 minutes"

## 2. What We're Building (0:45–2:00)

- Explain Agent Skills concept (30 sec)
  - Markdown files → AI learns specialized behavior
  - Drop in `.github/skills/` → always available
- Overview of the 5 skills (quick list)
- Explain Agentic Workflows (30 sec)
  - Automated tasks on schedule
  - Daily audit, PR gate, weekly coverage

## 3. Demo: Installing Skills (2:00–4:00)

- Start with a fresh Go project (or the demo repo)
- Show the one-liner installer:
  ```bash
  curl -fsSL .../install.sh | bash -s -- --repo .
  ```
- Walk through what was installed:
  - `.github/skills/` — the 5 skill files
  - `.github/agentic-workflows/` — 3 workflow templates
  - `config/severity.yaml` — customizable rules
- Show a SKILL.md file briefly — "this is all it takes"

## 4. Demo: Running an Audit (4:00–7:00)

- Open Copilot Chat / Claude Code
- Type: "Audit this code for quality issues"
- Show the skill activating and running:
  - `go vet` output
  - `golangci-lint` output
  - Categorized findings (🔴 Critical, 🟡 Warning, 🟢 Suggestion)
  - Quality score
- Show the API enhancement (if key is set):
  - Expert-level analysis beyond what tools catch
- Run `make audit` to show the script version

## 5. Demo: Coverage Analysis (7:00–9:00)

- "What tests am I missing?"
- Show coverage report:
  - Per-package breakdown
  - Uncovered functions highlighted
  - Missing test files identified
- Show test stub generation
- Run `make coverage` for the script version

## 6. Demo: Agentic Workflow PR (9:00–11:00)

- Set up the daily audit workflow:
  ```bash
  gh aw run daily-code-audit
  ```
- Show it running automatically
- Walk through the generated report/PR
- Show the PR quality gate:
  - Opens a PR → automatic review
  - Quality score, inline comments, recommendation

## 7. Customization (11:00–12:00)

- Show `severity.yaml` — quick edit
  - Promote `gofmt` to critical
  - Change coverage threshold
- Show how to add your own rules
- CI/CD integration snippet

## 8. Results Walkthrough (12:00–13:00)

- Before/after comparison:
  - Before: unchecked errors, missing godoc, no coverage
  - After: clean audit, full coverage, idiomatic code
- Show quality score improvement over time (concept)

## 9. Wrap Up + Links (13:00–14:00)

- Recap: 5 skills, 3 workflows, one-liner install
- Links (on screen):
  - GitHub: github.com/gopherguides/gopher-ai
  - Setup guide: .github/skills/SETUP.md
  - API docs: docs/api/README.md
  - Gopher Guides: gopherguides.com
- CTA: "Star the repo, try the demo, get your API key"
- "If this helped, like and subscribe"

---

## B-Roll / Screen Captures Needed

- [ ] Terminal: running install script
- [ ] Editor: Copilot Chat with audit prompt
- [ ] Terminal: audit.sh output with colored findings
- [ ] Terminal: coverage-report.sh output
- [ ] GitHub: agentic workflow PR with review
- [ ] Editor: severity.yaml being customized
- [ ] GitHub: before/after PR diff
