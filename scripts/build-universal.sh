#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

VERSION=$(jq -r '.metadata.version' "$ROOT_DIR/.claude-plugin/marketplace.json")

echo "Building universal distribution for gopher-ai v$VERSION"
echo "======================================================="

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

build_codex() {
    echo ""
    echo "Building Codex plugins..."
    echo "-------------------------"

    local codex_dir="$DIST_DIR/codex"
    mkdir -p "$codex_dir/plugins" "$codex_dir/skills"

    # Build Codex plugin packages for plugins with .codex-plugin/plugin.json
    for plugin_dir in "$ROOT_DIR"/plugins/*/; do
        plugin_name=$(basename "$plugin_dir")
        if [[ -f "${plugin_dir}.codex-plugin/plugin.json" ]]; then
            echo "  - Building plugin: $plugin_name"
            local dest="$codex_dir/plugins/$plugin_name"
            mkdir -p "$dest"
            cp -R "${plugin_dir}." "$dest/"
            rm -rf "$dest/.claude-plugin"
        fi
    done

    echo "  - Generating marketplace.json"
    generate_codex_marketplace > "$codex_dir/plugins/marketplace.json"

    for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
        if [[ -f "${skill_dir}SKILL.md" ]]; then
            skill_name=$(basename "$skill_dir")
            mkdir -p "$codex_dir/skills/$skill_name"
            cp "${skill_dir}"*.md "$codex_dir/skills/$skill_name/"
        fi
    done

    echo "  - Generating AGENTS.md"
    generate_agents_md > "$codex_dir/AGENTS.md"

    echo "  Done: $codex_dir"
}

generate_codex_marketplace() {
    local first=true
    echo '{'
    echo '  "name": "gopher-ai",'
    echo '  "interface": {'
    echo '    "displayName": "Gopher AI"'
    echo '  },'
    echo '  "plugins": ['
    for plugin_dir in "$ROOT_DIR"/plugins/*/; do
        plugin_name=$(basename "$plugin_dir")
        if [[ -f "${plugin_dir}.codex-plugin/plugin.json" ]]; then
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ','
            fi
            local category="Development"
            if [[ "$plugin_name" == "llm-tools" ]]; then
                category="Productivity"
            fi
            printf '    {\n      "name": "%s",\n      "source": { "source": "local", "path": "./.codex/plugins/%s" },\n      "policy": { "installation": "AVAILABLE", "authentication": "ON_USE" },\n      "category": "%s"\n    }' "$plugin_name" "$plugin_name" "$category"
        fi
    done
    echo ''
    echo '  ]'
    echo '}'
}

generate_agents_md() {
    cat << 'EOF'
# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit distributed as Codex plugins. Each plugin bundles related skills that activate automatically or can be invoked explicitly.

## Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| `go-workflow` | Issue-to-PR workflow automation | start-issue, create-worktree, commit, create-pr, ship, remove-worktree, prune-worktree, address-review, coverage |
| `go-dev` | Go development tools and best practices | go-best-practices, go-profiling-optimization, systematic-debugging, validate-skills |
| `gopher-guides` | Gopher Guides training materials | gopher-guides |
| `llm-tools` | Multi-LLM second opinions and delegation | second-opinion, gemini-image |
| `go-web` | Go web scaffolding (Templ + HTMX) | templui, htmx |
| `tailwind` | Tailwind CSS v4 tools | tailwind-best-practices |

## Workflow Skills (go-workflow plugin)

Invoke explicitly with `$skill-name`:

| Skill | Description |
|-------|-------------|
| `$start-issue <number>` | Full issue-to-PR workflow: fetch, branch, TDD, verify, submit |
| `$create-worktree <number>` | Create isolated git worktree for an issue or PR |
| `$commit` | Auto-generate conventional commit message |
| `$create-pr` | Create PR following repo template |
| `$ship` | Ship a PR: verify, push, create PR, watch CI, merge |
| `$remove-worktree` | Interactively remove a single worktree |
| `$prune-worktree` | Batch cleanup of completed worktrees |

### Example Workflow

```
$start-issue 42
# Codex fetches the issue, creates a worktree, detects bug vs feature,
# guides you through TDD implementation, verifies, and creates a PR.

$ship
# Verifies build/tests/lint, pushes, watches CI, and merges.

$prune-worktree
# Cleans up worktrees for closed issues.
```

## Installation

### Repo-Local (Recommended)

Codex reads `.agents/plugins/marketplace.json` on startup and syncs plugins automatically. Use `/plugins` to browse available plugins.

### Global (Personal) Installation

```bash
mkdir -p ~/.codex/plugins ~/.agents/plugins
cp -r dist/codex/plugins/* ~/.codex/plugins/
cp dist/codex/plugins/marketplace.json ~/.agents/plugins/marketplace.json
```

Restart Codex after installation. Use `/plugins` to verify.

### Flat Skills (Legacy)

```bash
cp -r dist/codex/skills/* ~/.codex/skills/
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git with worktree support
- `golangci-lint` (optional, for lint checks)

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
EOF
}

build_gemini() {
    echo ""
    echo "Building Gemini extensions..."
    echo "-----------------------------"

    local gemini_dir="$DIST_DIR/gemini"
    mkdir -p "$gemini_dir"

    for plugin_dir in "$ROOT_DIR"/plugins/*/; do
        plugin_name=$(basename "$plugin_dir")
        local ext_dir="$gemini_dir/gopher-ai-$plugin_name"
        mkdir -p "$ext_dir/skills" "$ext_dir/commands"

        echo "  Building extension: gopher-ai-$plugin_name"

        generate_gemini_extension_json "$plugin_name" > "$ext_dir/gemini-extension.json"

        generate_gemini_md "$plugin_name" > "$ext_dir/GEMINI.md"

        if [[ -d "${plugin_dir}skills/" ]]; then
            for skill_dir in "${plugin_dir}skills/"*/; do
                if [[ -f "${skill_dir}SKILL.md" ]]; then
                    skill_name=$(basename "$skill_dir")
                    mkdir -p "$ext_dir/skills/$skill_name"
                    cp "${skill_dir}"*.md "$ext_dir/skills/$skill_name/"
                fi
            done
        fi

        if [[ -d "${plugin_dir}agents/" ]]; then
            mkdir -p "$ext_dir/agents"
            for agent_file in "${plugin_dir}agents/"*.md; do
                if [[ -f "$agent_file" ]]; then
                    cp "$agent_file" "$ext_dir/agents/"
                fi
            done
        fi

        if [[ -d "${plugin_dir}commands/" ]]; then
            for cmd_file in "${plugin_dir}commands/"*.md; do
                if [[ -f "$cmd_file" ]]; then
                    cmd_name=$(basename "$cmd_file" .md)
                    convert_command_to_toml "$cmd_file" "$cmd_name" > "$ext_dir/commands/${cmd_name}.toml"
                fi
            done
        fi
    done

    echo "  Done: $gemini_dir"
}

generate_gemini_extension_json() {
    local plugin_name="$1"
    local plugin_json="$ROOT_DIR/plugins/$plugin_name/.claude-plugin/plugin.json"

    local description=""
    if [[ -f "$plugin_json" ]]; then
        description=$(jq -r '.description // ""' "$plugin_json")
    fi

    cat << EOF
{
  "name": "gopher-ai-$plugin_name",
  "version": "$VERSION",
  "description": "$description",
  "contextFileName": "GEMINI.md",
  "mcpServers": {},
  "excludeTools": [],
  "settings": []
}
EOF
}

generate_gemini_md() {
    local plugin_name="$1"
    local marketplace_desc=""

    marketplace_desc=$(jq -r --arg name "$plugin_name" '.plugins[] | select(.name == $name) | .description // ""' "$ROOT_DIR/.claude-plugin/marketplace.json")

    cat << EOF
# Gopher AI: $plugin_name

$marketplace_desc

## About

This extension is part of the gopher-ai toolkit for Go developers, created by [Gopher Guides](https://gopherguides.com).

## Skills

Skills in this extension activate automatically based on context. Check the \`skills/\` directory for available skills.

## Commands

Commands are available in the \`commands/\` directory. Each command is defined as a TOML file.

## Links

- [Gopher Guides Training](https://gopherguides.com)
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
EOF
}

convert_command_to_toml() {
    local cmd_file="$1"
    local cmd_name="$2"

    local description=""
    local argument_hint=""
    local model=""
    local allowed_tools=""

    local in_frontmatter=false
    local frontmatter=""

    while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
            if [[ "$in_frontmatter" == false ]]; then
                in_frontmatter=true
                continue
            else
                break
            fi
        fi
        if [[ "$in_frontmatter" == true ]]; then
            frontmatter+="$line"$'\n'
        fi
    done < "$cmd_file"

    description=$(echo "$frontmatter" | grep -E '^description:' | sed 's/^description:[[:space:]]*//' | tr -d '"' || echo "")
    argument_hint=$(echo "$frontmatter" | grep -E '^argument-hint:' | sed 's/^argument-hint:[[:space:]]*//' | tr -d '"' || echo "")
    model=$(echo "$frontmatter" | grep -E '^model:' | sed 's/^model:[[:space:]]*//' | tr -d '"' || echo "")
    allowed_tools=$(echo "$frontmatter" | grep -E '^allowed-tools:' | sed 's/^allowed-tools:[[:space:]]*//' || echo "")

    local exclude_tools="[]"
    if [[ -n "$allowed_tools" ]]; then
        exclude_tools=$(convert_allowlist_to_denylist "$allowed_tools")
    fi

    cat << EOF
# Generated from $cmd_name.md
# gopher-ai v$VERSION

[command]
name = "$cmd_name"
description = "$description"
EOF

    if [[ -n "$argument_hint" ]]; then
        echo "argumentHint = \"$argument_hint\""
    fi

    if [[ -n "$model" ]]; then
        echo "model = \"$model\""
    fi

    echo ""
    echo "[options]"
    echo "excludeTools = $exclude_tools"
}

convert_allowlist_to_denylist() {
    local allowlist="$1"

    local all_tools='["Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch", "Task", "TodoWrite", "AskUserQuestion", "NotebookEdit"]'

    if [[ "$allowlist" == *"Bash"* && "$allowlist" != *"Bash("* ]]; then
        echo "[]"
        return
    fi

    echo "[]"
}

create_archives() {
    echo ""
    echo "Creating distribution archives..."
    echo "----------------------------------"

    cd "$DIST_DIR"

    if [[ -d "codex" ]]; then
        tar -czf "gopher-ai-codex-skills-v${VERSION}.tar.gz" codex/
        echo "  - Created: gopher-ai-codex-skills-v${VERSION}.tar.gz"
    fi

    if [[ -d "gemini" ]]; then
        tar -czf "gopher-ai-gemini-extensions-v${VERSION}.tar.gz" gemini/
        echo "  - Created: gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
    fi

    cd "$ROOT_DIR"
}

print_summary() {
    echo ""
    echo "======================================================="
    echo "Build complete!"
    echo ""
    echo "Distribution structure:"
    echo ""
    if command -v tree &> /dev/null; then
        tree -L 3 "$DIST_DIR" 2>/dev/null || find "$DIST_DIR" -type f | head -20
    else
        find "$DIST_DIR" -type f | head -20
    fi
    echo ""
    echo "Installation instructions:"
    echo ""
    echo "  Codex CLI (plugins):"
    echo "    mkdir -p ~/.codex/plugins ~/.agents/plugins"
    echo "    cp -r dist/codex/plugins/* ~/.codex/plugins/"
    echo "    cp dist/codex/plugins/marketplace.json ~/.agents/plugins/marketplace.json"
    echo ""
    echo "  Codex CLI (flat skills, legacy):"
    echo "    cp -r dist/codex/skills/* ~/.codex/skills/"
    echo ""
    echo "  Gemini CLI:"
    echo "    gemini extensions install ./dist/gemini/gopher-ai-<plugin>"
    echo ""
}

main() {
    build_codex
    build_gemini
    create_archives
    print_summary
}

main "$@"
