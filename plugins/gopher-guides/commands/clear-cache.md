---
description: "Clear the Gopher Guides API response cache"
allowed-tools: ["Bash"]
---

# Clear Gopher Guides Cache

Remove cached API responses to force fresh data on next query.

## Execute

!`CACHE_FILE="${GOPHER_GUIDES_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gopher-ai/gopher-guides-cache.json}"; rm -f "$CACHE_FILE" && echo "✓ Gopher Guides cache cleared"`

## Result

The cache has been cleared. The next API call for each endpoint will fetch fresh data.
