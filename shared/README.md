# Shared Loop Infrastructure

This directory is the **single source of truth** for loop state management files used across multiple plugins.

## Architecture

Claude Code plugins require files to be local to the plugin directory (`${CLAUDE_PLUGIN_ROOT}`). Because of this, shared files are **copied** (not symlinked) to each plugin that needs them.

### Shared Files

| File | Purpose | Synced To |
|------|---------|-----------|
| `scripts/setup-loop.sh` | Initialize a persistent loop | All loop plugins |
| `scripts/cleanup-loop.sh` | Clean up loop state files | All loop plugins |
| `lib/loop-state.sh` | Shared functions for state management | All loop plugins |
| `commands/cancel-loop.md` | `/cancel-loop` command for users | All loop plugins |
| `hooks/stop-hook.sh` | Stop hook to intercept session exit | **go-workflow only** |

### Loop Plugins

These plugins receive copies of the shared files:
- `go-workflow` — Also gets `hooks/stop-hook.sh` (owns persistent loop management)
- `go-dev`
- `go-web`
- `tailwind`

## How Sync Works

1. **Edit files here** in `shared/` — this is the source of truth
2. **Run sync**: `./scripts/sync-shared.sh` copies files to all loop plugins
3. **Pre-commit hook**: Automatically syncs and stages files when `shared/` changes
4. **CI check**: `./scripts/check-shared-sync.sh` verifies all copies match (runs on every PR)

### Setup

Install the pre-commit hook (one-time):
```bash
./scripts/install-hooks.sh
```

### Manual Sync

After editing any file in `shared/`:
```bash
./scripts/sync-shared.sh
```

## Important Notes

- **Never edit the copies** in plugin directories directly — they will be overwritten by sync
- **Always edit in `shared/`** and run sync (or let the pre-commit hook do it)
- The `stop-hook.sh` references `../lib/loop-state.sh` relative to its own location, so the copy approach is required
- Commands use `${CLAUDE_PLUGIN_ROOT}/scripts/...` which resolves to the plugin's local copy
