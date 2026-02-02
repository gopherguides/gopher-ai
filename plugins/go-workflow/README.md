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

## Commands

| Command | Description |
|---------|-------------|
| `/start-issue <number>` | Start working on a GitHub issue (auto-detects bug vs feature) |
| `/address-review [PR]` | Address PR review comments, make fixes, reply, and resolve |
| `/create-worktree <number>` | Create a new git worktree for isolated issue work |
| `/commit` | Create a git commit with auto-generated message |
| `/remove-worktree` | Interactively select and remove a git worktree |
| `/prune-worktree` | Batch cleanup of all completed issue worktrees |

## Workflows

### Start Issue

The `/start-issue` command provides an intelligent issue-to-PR workflow:

1. **Fetches issue details** including all comments for full context
2. **Offers worktree creation** for isolated work (creates `../repo-issue-123-title/`)
3. **Auto-detects issue type** by analyzing labels, then title/body patterns
4. **Routes to appropriate workflow:**
   - **Bug fix**: Checks duplicates → TDD approach (failing test first) → `fix/` branch
   - **Feature**: Plans approach → Implementation → Tests → `feat/` branch
5. **Asks for clarification** if the type can't be determined automatically

### Address Review

The `/address-review` command handles PR review feedback automatically:

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
