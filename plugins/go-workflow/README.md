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
| `/create-worktree <number>` | Create a new git worktree for isolated issue work |
| `/commit` | Create a git commit with auto-generated message |
| `/remove-worktree` | Interactively select and remove a git worktree |
| `/prune-worktree` | Batch cleanup of all completed issue worktrees |

## Workflow

The `/start-issue` command provides an intelligent issue-to-PR workflow:

1. **Fetches issue details** including all comments for full context
2. **Offers worktree creation** for isolated work (creates `../repo-issue-123-title/`)
3. **Auto-detects issue type** by analyzing labels, then title/body patterns
4. **Routes to appropriate workflow:**
   - **Bug fix**: Checks duplicates → TDD approach (failing test first) → `fix/` branch
   - **Feature**: Plans approach → Implementation → Tests → `feat/` branch
5. **Asks for clarification** if the type can't be determined automatically

## Requirements

- GitHub CLI (`gh`) - authenticated
- Git with worktree support

## License

MIT - see [LICENSE](../../LICENSE)
