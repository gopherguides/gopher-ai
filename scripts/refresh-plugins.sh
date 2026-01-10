#!/bin/bash
# Refresh gopher-ai plugins - one and done
# Workaround for:
#   - https://github.com/anthropics/claude-code/issues/14061 (cache not invalidated on update)
#   - https://github.com/anthropics/claude-code/issues/15621 (old versions still run hooks)
set -e

MARKETPLACE_DIR="$HOME/.claude/plugins/marketplaces/gopher-ai"
CACHE_DIR="$HOME/.claude/plugins/cache/gopher-ai"
INSTALLED_FILE="$HOME/.claude/plugins/installed_plugins.json"
GLOBAL_CACHE_DIR="$HOME/.claude/plugins/cache"

echo "Refreshing gopher-ai plugins..."

# Step 0: Clean old cached versions of ALL plugins (addresses #15621)
# Old versions can still have their hooks executed even after updates
echo "- Cleaning old cached plugin versions..."
if [ -d "$GLOBAL_CACHE_DIR" ]; then
    for marketplace in "$GLOBAL_CACHE_DIR"/*/; do
        [ -d "$marketplace" ] || continue
        for plugin in "$marketplace"/*/; do
            [ -d "$plugin" ] || continue
            # Find the latest version (highest semver via sort -V, or alphabetically)
            latest=$(ls -v "$plugin" 2>/dev/null | tail -1)
            if [ -n "$latest" ]; then
                for version in "$plugin"/*/; do
                    [ -d "$version" ] || continue
                    version_name=$(basename "$version")
                    if [ "$version_name" != "$latest" ]; then
                        rm -rf "$version"
                        echo "  Removed stale: $(basename "$marketplace")/$(basename "$plugin")/$version_name"
                    fi
                done
            fi
        done
    done
fi

# Step 1: Update marketplace repo (get latest plugin definitions)
if [ -d "$MARKETPLACE_DIR" ]; then
    echo "- Pulling latest from marketplace repo..."
    git -C "$MARKETPLACE_DIR" fetch origin
    git -C "$MARKETPLACE_DIR" reset --hard origin/main
else
    echo "Marketplace not installed."
    echo "   Run: /plugin marketplace add gopherguides/gopher-ai"
    exit 1
fi

# Step 2: Clear plugin cache (forces fresh install)
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR"
    echo "- Cleared plugin cache"
fi

# Step 3: Remove ALL @gopher-ai plugins from installed_plugins.json
# This handles renamed/removed/added plugins automatically
if command -v jq &> /dev/null && [ -f "$INSTALLED_FILE" ]; then
    jq '.plugins |= with_entries(select(.key | endswith("@gopher-ai") | not))' \
        "$INSTALLED_FILE" > /tmp/installed_plugins.json.tmp \
        && mv /tmp/installed_plugins.json.tmp "$INSTALLED_FILE"
    echo "- Cleared all gopher-ai plugin registrations"
else
    echo "Warning: jq not found - cannot clean installed_plugins.json"
    echo "   Install jq: brew install jq"
fi

echo ""
echo "Done! Restart Claude Code to load updated plugins."
echo ""
echo "To install new plugins, run in Claude Code:"
echo "   /plugin install <plugin-name>@gopher-ai"
echo ""
echo "Available plugins: go-workflow, go-dev, productivity, gopher-guides, llm-tools, go-web, tailwind"
