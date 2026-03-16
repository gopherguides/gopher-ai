---
argument-hint: "[loop-name]"
description: "Cancel any active persistent loop"
allowed-tools: ["Bash"]
---

# Cancel Loop

Cancel the currently active persistent loop and allow normal session behavior.

**Usage:**
- `/cancel-loop` - Cancel all active loops
- `/cancel-loop <name>` - Cancel a specific loop by name

## Execute Cancellation

!`if [ -x "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" ]; then "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-loop.sh" "$ARGUMENTS"; else echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; fi`

## Result

The loop has been cancelled. You can now exit the session normally or start a new task.

If you want to restart the previous task, you can run the original command again.
