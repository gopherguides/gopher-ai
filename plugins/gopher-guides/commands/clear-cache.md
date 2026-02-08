---
description: "Clear the Gopher Guides API response cache"
allowed-tools: ["Bash"]
---

# Clear Gopher Guides Cache

Remove cached API responses to force fresh data on next query.

## Execute

!`rm -f .claude/gopher-guides-cache.json && echo "✓ Gopher Guides cache cleared"`

## Result

The cache has been cleared. The next API call for each endpoint will fetch fresh data.
