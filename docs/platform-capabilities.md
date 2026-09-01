# Platform capabilities

The canonical machine-readable inventory is
[`platform-capabilities.json`](platform-capabilities.json). Unsupported means a
capability is unavailable on that platform today, not that an installed plugin
provides an equivalent workflow by another name.

Shipped surface: 36 Claude Code commands across 7 plugins; 29 Codex skills across 6 plugins; 8 optional Codex MCP tools.

## Current matrix

| Plugin | Claude Code sources | Codex disposition |
| --- | --- | --- |
| `go-workflow` | Commands: `cancel-loop`, `create-worktree`, `prune-worktree`, `remove-worktree`. Skills: `address-review`, `cancel-loop`, `commit`, `complete-issue`, `create-pr`, `e2e-verify`, `review-deep`, `ship`, `start-issue`, `tmux-start`, `worktree`. | Skills: `$go-workflow:address-review`, `$go-workflow:cancel-loop`, `$go-workflow:commit`, `$go-workflow:complete-issue`, `$go-workflow:create-pr`, `$go-workflow:e2e-verify`, `$go-workflow:review-deep`, `$go-workflow:ship`, `$go-workflow:start-issue`, `$go-workflow:tmux-start`, `$go-workflow:worktree`. |
| `go-dev` | Commands: `bench`, `build-fix`, `cancel-loop`, `explain`, `lint-fix`, `profile`, `refactor-clean`, `test-gen`, `validate-skills`, `verify`. Skills: `bench`, `build-fix`, `explain`, `go`, `go-profiling-optimization`, `lint-fix`, `profile`, `refactor-clean`, `test-gen`, `validate-skills`, `verify`. | Skills: `$go-dev:bench`, `$go-dev:build-fix`, `$go-dev:explain`, `$go-dev:go`, `$go-dev:go-profiling-optimization`, `$go-dev:lint-fix`, `$go-dev:profile`, `$go-dev:refactor-clean`, `$go-dev:test-gen`, `$go-dev:validate-skills`, `$go-dev:verify`. `cancel-loop` is intentionally Claude-only and unsupported on Codex because it controls Claude persistent-loop hooks ([#333](https://github.com/gopherguides/gopher-ai/issues/333)). |
| `productivity` | Commands: `changelog`, `gopher-ai-refresh`, `release`, `standup`, `weekly-summary`. | Intentionally Claude-only; all five commands are unsupported. |
| `gopher-guides` | Command: `clear-cache`. Skill: `gopher-guides`. | Skill: `$gopher-guides:gopher-guides`. `clear-cache` is unsupported ([#337](https://github.com/gopherguides/gopher-ai/issues/337)). |
| `llm-tools` | Commands: `cancel-loop`, `codex`, `convert`, `gemini`, `gemini-image`, `llm-compare`, `ollama`, `review-loop`. Skills: `gemini-image`, `second-opinion`. | Skills: `$llm-tools:gemini-image`, `$llm-tools:second-opinion`. The remaining command workflows are unsupported ([#335](https://github.com/gopherguides/gopher-ai/issues/335)). |
| `go-web` | Commands: `cancel-loop`, `convert-to-go-project`, `create-go-project`. Skills: `convert-to-go-project`, `htmx`, `templui`. | Skills: `$go-web:convert-to-go-project`, `$go-web:htmx`, `$go-web:templui`. Conversion resolved [#323](https://github.com/gopherguides/gopher-ai/issues/323); `cancel-loop` and `create-go-project` are unsupported ([#334](https://github.com/gopherguides/gopher-ai/issues/334)). |
| `tailwind` | Commands: `audit`, `cancel-loop`, `init`, `migrate`, `optimize`. Skill: `tailwind-best-practices`. | Skill: `$tailwind:tailwind-best-practices`. All five command workflows are unsupported ([#336](https://github.com/gopherguides/gopher-ai/issues/336)). |

The optional Tailwind MCP server exposes `search_tailwind_docs`,
`get_tailwind_utilities`, `get_tailwind_colors`, `get_tailwind_config_guide`,
`install_tailwind`, `convert_css_to_tailwind`, `generate_color_palette`, and
`generate_component_template`. These supplementary tools do not replace the
end-to-end `audit`, `init`, `migrate`, or `optimize` workflows.
