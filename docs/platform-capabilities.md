# Platform capabilities

The canonical machine-readable inventory is
[`platform-capabilities.json`](platform-capabilities.json). Unsupported means a
capability is unavailable on that platform today, not that an installed plugin
provides an equivalent workflow by another name.

Shipped surface: 36 Claude Code commands across 7 plugins; 37 Codex skills across 6 plugins; 0 optional Codex MCP tools.

## Current matrix

| Plugin | Claude Code sources | Codex disposition |
| --- | --- | --- |
| `go-workflow` | Commands: `cancel-loop`, `create-worktree`, `prune-worktree`, `remove-worktree`. Skills: `address-review`, `cancel-loop`, `commit`, `complete-issue`, `create-pr`, `e2e-verify`, `review-deep`, `ship`, `start-issue`, `tmux-start`, `worktree`. | Skills: `$go-workflow:address-review`, `$go-workflow:cancel-loop`, `$go-workflow:commit`, `$go-workflow:complete-issue`, `$go-workflow:create-pr`, `$go-workflow:e2e-verify`, `$go-workflow:review-deep`, `$go-workflow:ship`, `$go-workflow:start-issue`, `$go-workflow:tmux-start`, `$go-workflow:worktree`. |
| `go-dev` | Commands: `bench`, `build-fix`, `cancel-loop`, `explain`, `lint-fix`, `profile`, `refactor-clean`, `test-gen`, `validate-skills`, `verify`. Skills: `bench`, `build-fix`, `explain`, `go`, `go-profiling-optimization`, `lint-fix`, `profile`, `refactor-clean`, `test-gen`, `validate-skills`, `verify`. | Skills: `$go-dev:bench`, `$go-dev:build-fix`, `$go-dev:explain`, `$go-dev:go`, `$go-dev:go-profiling-optimization`, `$go-dev:lint-fix`, `$go-dev:profile`, `$go-dev:refactor-clean`, `$go-dev:test-gen`, `$go-dev:validate-skills`, `$go-dev:verify`. `cancel-loop` is intentionally Claude-only and unsupported on Codex because it controls Claude persistent-loop hooks ([#333](https://github.com/gopherguides/gopher-ai/issues/333)). |
| `productivity` | Commands: `changelog`, `gopher-ai-refresh`, `release`, `standup`, `weekly-summary`. | Intentionally Claude-only; all five commands are unsupported. |
| `gopher-guides` | Command: `clear-cache`. Skills: `clear-cache`, `gopher-guides`. | Skills: `$gopher-guides:clear-cache`, `$gopher-guides:gopher-guides`. `clear-cache` resolves [#337](https://github.com/gopherguides/gopher-ai/issues/337). |
| `llm-tools` | Commands: `cancel-loop`, `codex`, `convert`, `gemini`, `gemini-image`, `llm-compare`, `ollama`, `review-loop`. Skills: `gemini`, `gemini-image`, `ollama`, `second-opinion`. | Skills: `$llm-tools:gemini`, `$llm-tools:gemini-image`, `$llm-tools:ollama`, `$llm-tools:second-opinion`. `cancel-loop`, Claude-to-Codex delegation, conversion, multi-provider comparison, and the persistent review loop remain intentionally unsupported on Codex ([#335](https://github.com/gopherguides/gopher-ai/issues/335)). |
| `go-web` | Commands: `cancel-loop`, `convert-to-go-project`, `create-go-project`. Skills: `convert-to-go-project`, `create-go-project`, `htmx`, `templui`. | Skills: `$go-web:convert-to-go-project`, `$go-web:create-go-project`, `$go-web:htmx`, `$go-web:templui`. Project conversion resolved [#323](https://github.com/gopherguides/gopher-ai/issues/323), and project creation resolved [#334](https://github.com/gopherguides/gopher-ai/issues/334); `cancel-loop` remains unsupported. |
| `tailwind` | Commands: `audit`, `cancel-loop`, `init`, `migrate`, `optimize`. Skills: `audit`, `init`, `migrate`, `optimize`, `tailwind-best-practices`. | Skills: `$tailwind:audit`, `$tailwind:init`, `$tailwind:migrate`, `$tailwind:optimize`, `$tailwind:tailwind-best-practices`. `cancel-loop` is intentionally Claude-only and unsupported on Codex because it controls Claude persistent-loop hooks ([#336](https://github.com/gopherguides/gopher-ai/issues/336)). |
