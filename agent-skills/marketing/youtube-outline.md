# YouTube Video Outline: Gopher AI Agent Skills

Target runtime: 12-15 minutes

Format: talking head intro and wrap-up with screen recording for installation,
agent prompts, terminal output, and GitHub PR workflow.

## Title Options

- Automated Go Code Quality with GitHub Agent Skills
- Give GitHub Copilot a Go Code Review Playbook
- Agent Skills for Go Audits, PR Review, Lint, and Coverage

## Audience

Go developers and team leads who want repeatable AI-assisted code quality checks
inside GitHub Copilot, Claude Code, Codex, or another compatible agent.

## Core Message

Gopher AI turns Go review standards into reusable Agent Skills. Install once,
commit the skills to `.github/skills/`, and let compatible agents run the same
audit, review, lint, standards, and coverage playbooks across the team.

## Segment Order

### 1. Hook

Talking head:

- "Every Go PR has the same baseline review chores: errors, tests, lint,
  package names, exported APIs, and concurrency checks."
- "Instead of writing that prompt every time, put the review playbook in the
  repo as Agent Skills."

Screen:

- Show the five skill folders under `agent-skills/skills/`.
- Open one `SKILL.md` to show `name`, `description`, and task instructions.

### 2. What Agent Skills Add

Screen:

- Show `agent-skills/README.md`.
- Highlight the five skills:
  - `go-code-audit`
  - `go-code-review`
  - `go-lint-audit`
  - `go-standards-audit`
  - `go-test-coverage`

Talking points:

- Skills are discoverable task instructions with optional bundled assets.
- They keep repeatable guidance in version control.
- The local path works without an API key; `GOPHER_GUIDES_API_KEY` only enables
  enhanced analysis.

### 3. Install in a Repository

Screen recording:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/agent-skills/scripts/install.sh) --repo .
tree .github/skills -L 2
tree .github/agentic-workflows -L 1
```

Callouts:

- Skills install to `.github/skills/`.
- Scripts install to `.github/skills/scripts/`.
- Severity config installs to `.github/skills/config/severity.yaml`.
- Workflow templates install to `.github/agentic-workflows/`.

### 4. Demo the Code Audit

Screen recording:

- Open `agent-skills/examples/demo-repo/main.go`.
- Point out intentional issues: unchecked errors, global mutable state, weak
  error handling, and incomplete tests.
- Ask the agent: "Audit this Go project for code quality issues."
- Run the helper script:

```bash
cd agent-skills/examples/demo-repo
make audit SKILLS_SCRIPTS=../../scripts
```

Talking points:

- The skill combines local tools with agent review.
- Findings are grouped by severity.
- The API-enhanced path is optional and should follow organization policy.

### 5. Demo Test Coverage

Screen recording:

```bash
make coverage SKILLS_SCRIPTS=../../scripts
```

Ask the agent:

```text
What tests am I missing?
```

Talking points:

- Coverage percentage alone is not enough.
- The useful output is the missing edge cases and error paths.
- The skill nudges toward table-driven tests.

### 6. PR Review Workflow

Screen recording:

- Show a local branch with a small Go change.
- Ask: "Review my changes before I open a pull request."
- Show the generated summary format:
  - must fix
  - should fix
  - nits
  - breaking changes
  - test recommendation

Talking points:

- The first-pass review is for predictable findings.
- Human reviewers still own product behavior, design, and tradeoffs.
- The goal is a cleaner PR before review starts.

### 7. CI/CD Integration

Screen recording:

- Open `agent-skills/SETUP.md`.
- Show the GitHub Actions example.
- Show optional secret setup:

```bash
gh secret set GOPHER_GUIDES_API_KEY --body "your-key-here"
```

Talking points:

- The same scripts can run in CI.
- The API key is optional.
- Teams can customize severity in `.github/skills/config/severity.yaml`.

### 8. Wrap Up

Talking head:

- "Install the skills, commit `.github/skills/`, and start using the same Go
  quality baseline in every repo."
- Mention the repo path:
  <https://github.com/gopherguides/gopher-ai/tree/main/agent-skills>

Screen:

- End on `agent-skills/README.md` with the install command visible.

## Shot List

- Talking head intro
- Repo tree showing `agent-skills/`
- `SKILL.md` frontmatter close-up
- Terminal install command
- `.github/skills/` installed tree
- Demo repo audit output
- Coverage output
- Generated PR review summary
- GitHub Actions YAML from setup guide
- Talking head wrap-up

## Assets to Capture

- Screenshot: audit report with severity sections
- Screenshot: PR review summary or comment
- Screenshot: coverage report
- Terminal recording: installer command
- Terminal recording: demo audit and coverage commands
- Browser capture: Gopher AI GitHub repo Agent Skills README

## Description Draft

Gopher AI Agent Skills give GitHub Copilot and compatible coding agents reusable
Go code quality workflows: project audits, PR review, lint explanations, Gopher
Guides standards checks, and test coverage analysis. This walkthrough installs
the skills into `.github/skills/`, runs them on a demo Go project, and shows how
to wire the helper scripts into CI.

Links:

- Gopher AI Agent Skills: https://github.com/gopherguides/gopher-ai/tree/main/agent-skills
- Setup guide: https://github.com/gopherguides/gopher-ai/blob/main/agent-skills/SETUP.md
