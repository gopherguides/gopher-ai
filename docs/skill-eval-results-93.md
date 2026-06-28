# Skill Eval Results for Issue 93

Issue #93 asked for a Claude Code-style "test, measure, iterate" review of
plugin skills. The original issue listed 5 skills, but the active marketplace
now has 19 plugin skills. This review covers `plugins/*/skills/*/SKILL.md` only.
The `agent-skills/skills/` directory is a separate distributable Agent Skills
surface and is tracked outside this issue.

## Method

Each skill was evaluated with four checks:

- Recall: prompts that should activate the skill.
- Precision: near-miss prompts that should not activate the skill, or should
  route to a sibling skill.
- Output quality: whether the loaded instructions tell the agent what to do,
  what to avoid, and which reference file to read next.
- Tool permissions: whether frontmatter grants are obviously missing or broader
  than the skill body needs.

This repository does not include a Claude Code activation runner. Results below
are a manual prompt-run classification against the current frontmatter and
skill bodies, followed by description/content edits where the expected route was
ambiguous.

## Summary

- Scope reviewed: 19 plugin skills.
- Existing machine-readable output-quality evals found: `go` and
  `go-profiling-optimization`.
- Description iterations made: `go`, `gopher-guides`, `htmx`, `templui`,
  `address-review`, `commit`, `complete-issue`, `e2e-verify`, `review-deep`,
  `start-issue`, `gemini-image`.
- Content fix made: `gopher-guides` no longer describes REST-backed behavior as
  MCP-backed in frontmatter, and its direct curl example now uses
  `--variable`/`--expand-header` like the rest of the file.
- Tool-permission result: no blocking permission defects found. The highest-risk
  mutating workflow skills already declare explicit tool lists or disable model
  invocation. Several smaller router/reference skills intentionally omit
  `allowed-tools`; no new broad grants were added.

## Overlap Findings

### `go` vs `gopher-guides`

Expected routing:

- Use `go` for general idiomatic Go implementation, review, debugging, tests,
  package design, concurrency, and errors.
- Use `gopher-guides` only when the user explicitly asks for Gopher Guides,
  professional training material, curated practices/examples, or API-backed
  audit output.

Iteration:

- `go` now skips explicit Gopher Guides training/API requests.
- `gopher-guides` now says REST API/cache wrapper instead of MCP and requires
  explicit training-material-backed intent.

### Workflow Skills

Expected routing:

- `start-issue`: begin issue implementation and submit a PR.
- `complete-issue`: autonomous issue-to-merged-PR flow.
- `create-pr`: open/submit PR without merge.
- `ship`: verify, push, CI, review feedback, merge.
- `review-deep`: fresh quality/spec review.
- `address-review`: existing review feedback and thread resolution.
- `e2e-verify`: browser/UI verification.

Iteration:

- Added skip rules for the main confusing pairs:
  `start-issue`/`complete-issue`, `review-deep`/`address-review`,
  `e2e-verify`/backend-only checks, and `commit`/PR-or-ship flows.

### Web Skills

Expected routing:

- `htmx`: `hx-*`, swaps, triggers, OOB, SSE/WebSockets, and htmx-aware Go
  handlers.
- `templui`: templUI components, Script() setup, templ interpolation, and
  templUI-specific conversion/audit.
- `tailwind-best-practices`: Tailwind v4 utilities, `@theme`, `@source`, dark
  mode, responsive design, and v3-to-v4 differences.

Iteration:

- `htmx` now skips generic web/fetch/AJAX/templUI prompts without htmx context.
- `templui` now skips generic htmx issues with no templUI/component context.

### Image And Second-Opinion Skills

Expected routing:

- `gemini-image`: generation/editing of visual output.
- `second-opinion`: high-stakes or ambiguous technical decisions where another
  model family is useful.

Iteration:

- `gemini-image` now skips screenshot inspection and image analysis with no
  generation/edit request.

## Eval Matrix

### `go`

- Recall probes:
  - "Is this Go interface too broad?"
  - "Write table-driven tests for this `_test.go` file."
  - "Why is this goroutine leaking?"
- Precision probes:
  - "Profile this endpoint with pprof." -> `go-profiling-optimization`
  - "What would Gopher Guides recommend for this handler?" -> `gopher-guides`
- Output quality result: pass. The skill routes by topic and points to focused
  sibling references.
- Iteration: added explicit skip for Gopher Guides training/API requests.

### `go-profiling-optimization`

- Recall probes:
  - "Why is this Go service allocating so much?"
  - "Run pprof and reduce p99 latency."
  - "Compare benchmark results with benchstat."
- Precision probes:
  - "Is this Go package name idiomatic?" -> `go`
  - "How do I write a unit test?" -> `go`
- Output quality result: pass. The skill enforces measure-before-optimize and
  already has 10 output-quality evals.
- Iteration: none.

### `validate-skills`

- Recall probes:
  - "I edited `plugins/go-dev/commands/validate-skills.md`; check shell blocks."
  - "CI says a markdown bash block has an unclosed quote."
- Precision probes:
  - "Lint this Go package." -> `go`
  - "Validate an arbitrary README with no shell examples." -> no skill
- Output quality result: pass. It documents syntax, shellcheck, portability, and
  unsafe-command checks.
- Iteration: none.

### `htmx`

- Recall probes:
  - "This templ row has `hx-get` and `hx-swap`; is it correct?"
  - "How should a Go handler return an htmx fragment?"
  - "Use `HX-Trigger` to reload a list after delete."
- Precision probes:
  - "Use fetch to POST JSON from React." -> no skill
  - "Add a templUI dialog component." -> `templui`
- Output quality result: pass. Reference routing is clear and split by templ,
  Go handlers, attributes, and advanced patterns.
- Iteration: added skip for generic web/fetch/AJAX/templUI prompts without htmx
  context.

### `templui`

- Recall probes:
  - "Add a templUI dropdown to this templ layout."
  - "Why is my templUI dialog not opening?"
  - "Interpolate Go state into a templ Script() template."
- Precision probes:
  - "What does `hx-trigger='load'` do?" -> `htmx`
  - "Style this React component with Tailwind." -> `tailwind-best-practices`
- Output quality result: pass. It clearly states templUI is vanilla JavaScript
  and routes to component, Script(), interpolation, and conversion docs.
- Iteration: added skip for generic htmx issues without templUI/component
  context.

### `tailwind-best-practices`

- Recall probes:
  - "Convert this CSS card to Tailwind v4 utilities."
  - "How do I configure `@theme` colors?"
  - "Audit these responsive Tailwind classes."
- Precision probes:
  - "Write plain CSS grid with no Tailwind." -> no skill
  - "Use Bootstrap spacing utilities." -> no skill
- Output quality result: pass. It identifies MCP tools and fallback reference
  docs for v4 syntax, anti-patterns, and quick-reference patterns.
- Iteration: none.

### `address-review`

- Recall probes:
  - "Address the CodeRabbit comments on PR 42."
  - "Fix the requested changes and resolve review threads."
  - "Apply codex review findings on this PR."
- Precision probes:
  - "Review my changes before I open a PR." -> `review-deep`
  - "Ship this PR." -> `ship`
- Output quality result: pass. It has explicit loop, feedback, fix, CI, reply,
  and resolution phases.
- Iteration: added skip for fresh review requests with no existing feedback.

### `commit`

- Recall probes:
  - "Commit these staged changes."
  - "Save my work with a conventional commit."
- Precision probes:
  - "Open a PR." -> `create-pr`
  - "Push and merge this." -> `ship`
- Output quality result: pass. It checks status, default-branch protection,
  diff context, and conventional commit style.
- Iteration: clarified that it does not push or open PRs.

### `complete-issue`

- Recall probes:
  - "Complete issue #93 end to end."
  - "Finish this issue all the way to merge."
- Precision probes:
  - "Start issue #93 but leave it for review." -> `start-issue`
  - "Just open a PR." -> `create-pr`
- Output quality result: pass. It chains start, review, e2e, and ship with loop
  re-entry.
- Iteration: added skip for issue startup without merge intent.

### `create-pr`

- Recall probes:
  - "Open a PR for this branch."
  - "Submit a PR but do not merge it."
- Precision probes:
  - "Ship it." -> `ship`
  - "Commit these changes." -> `commit`
- Output quality result: pass. It gathers branch context, pushes, finds a PR
  template, links issues, and reports the URL.
- Iteration: none.

### `e2e-verify`

- Recall probes:
  - "Browser-test this PR."
  - "Verify the UI changes visually."
  - "Run e2e verification before merge."
- Precision probes:
  - "Run backend unit tests only." -> no skill or `review-deep`
  - "Address review comments." -> `address-review`
- Output quality result: pass. Visual screenshot inspection is repeatedly
  reinforced and the mode table is explicit.
- Iteration: added skip for backend-only checks with no browser/UI path.

### `review-deep`

- Recall probes:
  - "Review my changes against the issue."
  - "Check this PR for bugs and missing requirements."
  - "Do a post-implementation quality review."
- Precision probes:
  - "Resolve the reviewer comments." -> `address-review`
  - "Run only browser e2e." -> `e2e-verify`
- Output quality result: pass. It gathers PR/issue context, review threads,
  static analysis, criteria, output format, and fix/verify flow.
- Iteration: added skip for existing review feedback requiring replies/thread
  resolution.

### `ship`

- Recall probes:
  - "Ship it."
  - "Push and merge this PR."
  - "Land this branch after CI is green."
- Precision probes:
  - "Open a PR but do not merge." -> `create-pr`
  - "Commit this locally only." -> `commit`
- Output quality result: pass for high-level routing. The richer ship command
  remains the authoritative implementation path for repository-specific gates.
- Iteration: none.

### `start-issue`

- Recall probes:
  - "Start issue #93."
  - "Begin implementation for this GitHub issue URL."
  - "Work on issue #93 and submit a PR."
- Precision probes:
  - "Complete and merge issue #93." -> `complete-issue`
  - "Create a worktree only." -> `worktree`
- Output quality result: pass. It fetches issue context, handles worktree choice,
  TDD, verification, PR creation, and CI.
- Iteration: added skip for fully autonomous issue-to-merge requests.

### `tmux-start`

- Recall probes:
  - "Start issue #93 in a new tmux window."
  - "Create a worktree and let Claude continue in tmux."
- Precision probes:
  - "Start issue #93 in this session." -> `start-issue`
  - "Create a worktree but do not start Claude." -> `worktree`
- Output quality result: pass. It validates tmux, creates/reuses a worktree, and
  launches the workflow in a named window.
- Iteration: none.

### `worktree`

- Recall probes:
  - "Create a worktree for issue #93."
  - "Remove this issue worktree."
  - "Prune completed worktrees."
- Precision probes:
  - "Start the issue implementation." -> `start-issue`
  - "Commit changes in this branch." -> `commit`
- Output quality result: pass. It routes create/remove/prune to sibling docs and
  documents safety conventions.
- Iteration: none.

### `gopher-guides`

- Recall probes:
  - "What would Gopher Guides recommend for this error-handling code?"
  - "Use the Gopher Guides training material to audit this package."
  - "Show a professional Gopher Guides example of table-driven tests."
- Precision probes:
  - "Is this Go code idiomatic?" -> `go`
  - "Profile this Go function." -> `go-profiling-optimization`
- Output quality result: revised. The behavior is clear, but the description
  said MCP while the body uses REST/cache scripts, and one direct curl example
  contradicted the file's shell-expansion warning.
- Iteration: corrected the description and direct API example.

### `gemini-image`

- Recall probes:
  - "Generate a hero image for this app."
  - "Create a logo concept with Gemini."
  - "Edit this reference image into a banner."
- Precision probes:
  - "Inspect this screenshot for layout bugs." -> browser/image-inspection path
  - "Find images on the web." -> no skill
- Output quality result: pass. It confirms intent, gathers model/aspect/size/tier
  details, delegates request JSON handling, and saves output metadata.
- Iteration: added skip for screenshot inspection and image analysis without
  generation/editing intent.

### `second-opinion`

- Recall probes:
  - "Sanity check this architecture choice."
  - "Should we use Postgres advisory locks or a job queue?"
  - "Review this authentication design from another model's perspective."
- Precision probes:
  - "Fix this typo."
  - "Just implement the already-decided approach."
- Output quality result: pass. It defines trigger categories, non-trigger
  conditions, cross-model selection, and privacy guidance.
- Iteration: none.
