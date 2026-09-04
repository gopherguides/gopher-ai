---
description: "Clear the Gopher Guides API response cache"
allowed-tools: ["Bash"]
---

# Clear Gopher Guides Cache

Remove cached API responses to force fresh data on next query.

## Execute

!`/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/clear-cache.sh"`

## Result

The reported Gopher Guides cache targets have been cleared. The next API call for each endpoint will fetch fresh data.
