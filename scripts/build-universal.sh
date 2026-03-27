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
    echo "Building Codex skills..."
    echo "------------------------"

    local codex_dir="$DIST_DIR/codex"
    local repo_agents_dir="$ROOT_DIR/.agents/skills"
    mkdir -p "$codex_dir/skills"

    rm -rf "$repo_agents_dir"
    mkdir -p "$repo_agents_dir"

    for skill_dir in "$ROOT_DIR"/plugins/*/skills/*/; do
        if [[ -f "${skill_dir}SKILL.md" ]]; then
            skill_name=$(basename "$skill_dir")
            echo "  - Copying skill: $skill_name"
            mkdir -p "$codex_dir/skills/$skill_name"
            cp "${skill_dir}"*.md "$codex_dir/skills/$skill_name/"
            mkdir -p "$repo_agents_dir/$skill_name"
            cp "${skill_dir}"*.md "$repo_agents_dir/$skill_name/"
        fi
    done

    echo "  - Generating AGENTS.md"
    generate_agents_md > "$codex_dir/AGENTS.md"

    echo "  - Populated repo-level .agents/skills/ ($(find "$repo_agents_dir" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') skills)"
    echo "  Done: $codex_dir"
}

generate_agents_md() {
    cat << 'EOF'
# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Available Skills

Skills auto-activate based on context, or invoke directly with `$skill-name`.

### Go Development

| Skill | Triggers |
|-------|----------|
| `go-best-practices` | Go code, patterns, reviews, "best way to..." |
| `go-profiling-optimization` | Performance, profiling, benchmarks, "why is this slow" |
| `systematic-debugging` | Debugging, test failures, stack traces, "why is this broken" |
| `gopher-guides` | Go training materials, idiomatic patterns |

### Code Quality

| Skill | Triggers |
|-------|----------|
| `validate-skills` | Editing command/skill .md files, shell code validation |
| `address-review` | PR review comments, reviewer feedback, unresolved threads |

### Web Development

| Skill | Triggers |
|-------|----------|
| `tailwind-best-practices` | Tailwind CSS classes, themes, v4 config |
| `templui` | Go/Templ web apps, templUI components, HTMX/Alpine.js |
| `htmx` | htmx attributes, partial page updates, SSE, swaps |

### Multi-LLM

| Skill | Triggers |
|-------|----------|
| `second-opinion` | Architecture decisions, security code, "sanity check" |
| `gemini-image` | Image generation requests |

## Installation

### Via Codex skill installer (recommended)

```
codex> $skill-installer gopherguides/gopher-ai
```

### One-liner install

```bash
# User-level (available across all projects)
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --user

# Repo-level (available to all contributors)
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --repo .
```

### Manual install

```bash
git clone https://github.com/gopherguides/gopher-ai
cd gopher-ai
./scripts/build-universal.sh
cp -r dist/codex/skills/* ~/.agents/skills/
```

### Skill locations

| Scope | Path | Use case |
|-------|------|----------|
| Repo-level | `.agents/skills/` | Shared team standards (committed to repo) |
| User-level | `$HOME/.agents/skills/` | Personal toolkit across all projects |
| Legacy | `~/.codex/skills/` | Still loaded for backward compatibility |

> **Migrating from `~/.codex/skills/`?** Move your skills to `~/.agents/skills/` — Codex scans both paths, but `.agents/skills/` is the current convention.

## Updating

Re-run the installer to replace existing skills:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-codex.sh) --user
```

Or update manually:

```bash
rm -rf ~/.agents/skills/{go-best-practices,second-opinion,tailwind-best-practices,templui,gopher-guides,go-profiling-optimization,systematic-debugging,validate-skills,htmx,address-review,gemini-image}
cp -r dist/codex/skills/* ~/.agents/skills/
```

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
    echo "  Codex CLI (user-level):"
    echo "    cp -r dist/codex/skills/* ~/.agents/skills/"
    echo "    cp dist/codex/AGENTS.md ./AGENTS.md"
    echo ""
    echo "  Codex CLI (legacy path, still supported):"
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
