#!/bin/bash
# Refresh gopher-ai plugins by clearing all caches
#
# This is a workaround for a Claude Code bug where `/plugin marketplace update`
# doesn't properly refresh cached plugin files.
# See: https://github.com/anthropics/claude-code/issues/14061

set -e

echo "Refreshing gopher-ai plugins..."

# Clear plugin cache
if [ -d ~/.claude/plugins/cache/gopher-ai ]; then
    rm -rf ~/.claude/plugins/cache/gopher-ai/
    echo "- Cleared plugin cache"
fi

# Clear marketplace cache
if [ -d ~/.claude/plugins/marketplaces/gopher-ai ]; then
    rm -rf ~/.claude/plugins/marketplaces/gopher-ai/
    echo "- Cleared marketplace cache"
fi

# Clean installed_plugins.json
if command -v jq &> /dev/null && [ -f ~/.claude/plugins/installed_plugins.json ]; then
    jq 'del(.plugins["go-workflow@gopher-ai"], .plugins["go-dev@gopher-ai"], .plugins["productivity@gopher-ai"], .plugins["gopher-guides@gopher-ai"], .plugins["go-web@gopher-ai"], .plugins["llm-tools@gopher-ai"])' \
        ~/.claude/plugins/installed_plugins.json > /tmp/installed_plugins.json.tmp \
        && mv /tmp/installed_plugins.json.tmp ~/.claude/plugins/installed_plugins.json
    echo "- Cleaned installed_plugins.json"
fi

# Clean known_marketplaces.json
if command -v jq &> /dev/null && [ -f ~/.claude/plugins/known_marketplaces.json ]; then
    jq 'del(.["gopher-ai"])' \
        ~/.claude/plugins/known_marketplaces.json > /tmp/known_marketplaces.json.tmp \
        && mv /tmp/known_marketplaces.json.tmp ~/.claude/plugins/known_marketplaces.json
    echo "- Cleaned known_marketplaces.json"
fi

echo ""
echo "Cache cleared! Now:"
echo "1. Restart Claude Code (exit and reopen)"
echo "2. Run this command (auto-installs all plugins):"
echo "   /plugin marketplace add gopherguides/gopher-ai"
