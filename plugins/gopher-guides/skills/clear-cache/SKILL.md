---
name: clear-cache
description: "Clears Gopher Guides API response cache data and reports each resolved target. Use when cached training guidance must be refreshed; do not use to clear Codex, Claude, or unrelated application caches."
---

# Clear Gopher Guides Cache

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Run the packaged cache helper:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/clear-cache.sh"
```

Return the helper's resolved cache target output. It removes only the configured Gopher Guides cache file and, when no explicit override is configured, the current project's legacy Claude-era Gopher Guides cache file. It does not remove cache directories or unrelated files.
