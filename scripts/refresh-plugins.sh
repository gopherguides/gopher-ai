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

# Step 2: Update plugin cache in-place (keeps hooks working in current session)
# Instead of deleting the cache (which breaks hooks mid-session), we sync
# the latest plugin content directly into the cache directories.
echo "- Updating plugin cache..."
GIT_SHA=$(git -C "$MARKETPLACE_DIR" rev-parse HEAD)
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Determine copy command (prefer rsync, fall back to cp)
if command -v rsync &> /dev/null; then
    copy_cmd="rsync"
else
    copy_cmd="cp"
fi

# Track which plugins we updated (for installed_plugins.json)
UPDATED_PLUGINS=()

for plugin_dir in "$MARKETPLACE_DIR"/plugins/*/; do
    [ -d "$plugin_dir" ] || continue
    plugin_name=$(basename "$plugin_dir")
    version=$(jq -r '.version' "$plugin_dir/.claude-plugin/plugin.json")
    if [ -z "$version" ] || [ "$version" = "null" ]; then
        echo "  Error: missing version in $plugin_dir/.claude-plugin/plugin.json — skipping"
        continue
    fi
    dest="$CACHE_DIR/$plugin_name/$version"

    # Remove any OTHER versions of this plugin (stale)
    if [ -d "$CACHE_DIR/$plugin_name" ]; then
        for old_ver in "$CACHE_DIR/$plugin_name"/*/; do
            [ -d "$old_ver" ] || continue
            if [ "$(basename "$old_ver")" != "$version" ]; then
                rm -rf "$old_ver"
                echo "  Removed stale: $plugin_name/$(basename "$old_ver")"
            fi
        done
    fi

    # Copy current version into cache
    mkdir -p "$dest"
    if [ "$copy_cmd" = "rsync" ]; then
        rsync -a --delete "$plugin_dir/" "$dest/"
    else
        rm -rf "$dest"
        cp -a "$plugin_dir" "$dest"
    fi
    echo "  Updated: $plugin_name/$version"
    UPDATED_PLUGINS+=("$plugin_name:$version")
done

# Remove plugins from cache that no longer exist in marketplace
if [ -d "$CACHE_DIR" ]; then
    for cached_plugin in "$CACHE_DIR"/*/; do
        [ -d "$cached_plugin" ] || continue
        cached_name=$(basename "$cached_plugin")
        if [ ! -d "$MARKETPLACE_DIR/plugins/$cached_name" ]; then
            rm -rf "$cached_plugin"
            echo "  Removed orphan: $cached_name"
        fi
    done
fi

# Step 3: Re-register plugins in installed_plugins.json
if command -v jq &> /dev/null; then
    TMPFILE=$(mktemp)
    TMPFILE2=$(mktemp)
    trap 'rm -f "$TMPFILE" "$TMPFILE2"' EXIT

    # Start with existing file or empty structure
    if [ -f "$INSTALLED_FILE" ]; then
        # Remove old gopher-ai entries first
        jq '.plugins |= with_entries(select(.key | endswith("@gopher-ai") | not))' \
            "$INSTALLED_FILE" > "$TMPFILE"
    else
        echo '{"version":2,"plugins":{}}' > "$TMPFILE"
    fi

    # Add fresh entries for each updated plugin
    for entry in "${UPDATED_PLUGINS[@]}"; do
        p_name="${entry%%:*}"
        p_version="${entry##*:}"
        jq --arg name "${p_name}@gopher-ai" \
           --arg path "$CACHE_DIR/$p_name/$p_version" \
           --arg ver "$p_version" \
           --arg ts "$NOW" \
           --arg sha "$GIT_SHA" \
           '.plugins[$name] = [{
                "scope": "project",
                "installPath": $path,
                "version": $ver,
                "installedAt": $ts,
                "lastUpdated": $ts,
                "gitCommitSha": $sha,
                "projectPath": env.HOME
            }]' "$TMPFILE" > "$TMPFILE2" \
            && mv "$TMPFILE2" "$TMPFILE"
    done
    mv "$TMPFILE" "$INSTALLED_FILE"
    echo "- Updated plugin registrations"
else
    echo "Warning: jq not found - cannot update installed_plugins.json"
    echo "   Install jq: brew install jq"
fi

echo ""
echo "Done! Plugins updated in-place — hooks remain functional."
echo "Restart Claude Code to fully reload plugin definitions."
