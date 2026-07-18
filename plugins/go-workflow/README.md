# go-workflow

Issue-to-PR workflow automation with git worktree management.

## Installation

```bash
/plugin install go-workflow@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Workflow Skills and Commands

| Claude Code invocation | Description |
|------------------------|-------------|
| `/go-workflow:start-issue <number>` | Start working on a GitHub issue (auto-detects bug vs feature) |
| `/go-workflow:address-review [PR]` | Address PR review comments, fix, and loop until bots approve |
| `/go-workflow:review-deep [PR]` | Deep code review with full PR context, then fix findings |
| `/go-workflow:commit` | Create a git commit with auto-generated message |
| `/go-workflow:create-pr` | Create a PR following the repo template |
| `/go-workflow:e2e-verify [PR]` | Run browser E2E verification on a PR |
| `/go-workflow:ship` | Verify, push, watch CI/reviews, and merge |
| `/go-workflow:create-worktree <number>` | Create a new git worktree for isolated issue work |
| `/go-workflow:remove-worktree` | Interactively select and remove a git worktree |
| `/go-workflow:prune-worktree` | Batch cleanup of all completed issue worktrees |

## Skill Invocation Modes

| Mode | Skills |
|------|--------|
| Slash-only | `start-issue`, `address-review`, `worktree` (`/create-worktree`, `/remove-worktree`, `/prune-worktree`), `e2e-verify`, `ship`, `complete-issue`, `tmux-start` |
| Auto-triggerable | `commit`, `create-pr`, `review-deep` |

Slash-only skills still run through their slash commands, but their descriptions are omitted from the always-loaded auto-invoked skill list. Use `/go-workflow:<command>` in Claude Code or `$<skill>` in Codex. In Claude Code, type the slash command directly; `$start-issue` is Codex syntax and causes a blocked Skill-tool invocation. Auto-triggerable skills remain available from natural-language requests such as "commit these changes" or "review my changes".

## Workflows

### Start Issue

The `start-issue` skill provides an intelligent issue-to-PR workflow:

1. **Fetches issue details** including all comments for full context
2. **Offers worktree creation** for isolated work (creates `../repo-issue-123-title/`)
3. **Auto-detects issue type** by analyzing labels, then title/body patterns
4. **Routes to appropriate workflow:**
   - **Bug fix**: Checks duplicates → TDD approach (failing test first) → `fix/` branch
   - **Feature**: Plans approach → Implementation → Tests → `feat/` branch
5. **Asks for clarification** if the type can't be determined automatically

#### Subagent Model Tiering

The default orchestrated flow routes read-heavy and review subagents through
rolling model aliases in agent prompt frontmatter:

| Agent | Model policy |
|-------|--------------|
| Explore | Haiku |
| Implementer | Inherits the parent session model |
| Spec Review | Sonnet |
| Quality Review | Sonnet |

Set `CLAUDE_CODE_SUBAGENT_MODEL=<model>` before running `$start-issue` or
`$complete-issue` to override all subagent models for that run. Use
`--no-agents` to switch to the single-session workflow.

#### Codex Model Defaults

The `$ship` and `$complete-issue` Codex review stages omit model flags by
default. A `model = "..."` pin in `~/.codex/config.toml` overrides the provider
default for those stages; leaving it unset lets the Codex CLI use its latest
recommended model automatically.

### Address Review

The `$address-review` skill handles PR review feedback automatically:

1. **Fetches all feedback** - Review threads (line comments) and pending reviews
2. **Addresses each comment** - Makes code fixes based on feedback
3. **Watches CI** - Ensures all checks pass before continuing
4. **Resolves threads** - Auto-resolves line-specific review threads via GraphQL
5. **Requests re-review** - Automatically triggers re-review from reviewers

#### Auto Bot Re-review

When bot reviewers (Codex, CodeRabbit, Greptile, etc.) leave feedback, the skill automatically requests re-review by posting `@bot review` comments.

**Supported bots:**
- `codex` → `@codex review`
- `coderabbitai` → `@coderabbitai review`
- `greptileai` → `@greptileai review`
- `copilot` → Added via GitHub Reviewers

**To disable auto bot re-review**, add to your project's CLAUDE.md:
```markdown
## Bot Review Settings
DISABLE_BOT_REREVIEW=true
```

## Requirements

- GitHub CLI (`gh`) - authenticated
- Git with worktree support

## License

MIT - see [LICENSE](../../LICENSE)
