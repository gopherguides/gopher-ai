---
argument-hint: ""
description: "Refresh all gopher-ai plugins (clear cache + reinstall)"
allowed-tools: ["Bash(bash:*)"]
model: haiku
---

# Refresh Gopher-AI Plugins

This command clears the Claude Code plugin cache and refreshes all gopher-ai plugins to their latest versions.

**Use this when:**
- You've updated plugins and need to load the new versions
- Plugins are behaving unexpectedly
- After pulling new plugin changes from the repo

## Execution

Run the refresh script:

```bash
"$HOME/.claude/plugins/marketplaces/gopher-ai/scripts/refresh-plugins.sh"
```

**Note:** After running, restart Claude Code to load the updated plugins.
