#!/bin/bash
set -euo pipefail

export COPYFILE_DISABLE=1
export COPY_EXTENDED_ATTRIBUTES_DISABLE=1

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
    mkdir -p "$codex_dir/plugins"

    # Build Codex plugin packages for plugins with .codex-plugin/plugin.json
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        plugin_name=$(basename "$plugin_dir")
        if [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]]; then
            echo "  - Building plugin: $plugin_name"
            local dest="$codex_dir/plugins/$plugin_name"
            mkdir -p "$dest"
            cp -R "$plugin_dir"/. "$dest/"
            rm -rf "$dest/.claude-plugin"
        fi
    done

    echo "  - Generating marketplace.json"
    generate_codex_marketplace > "$codex_dir/plugins/marketplace.json"

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
    if [[ -f "$ROOT_DIR/AGENTS.md" ]]; then
        cat "$ROOT_DIR/AGENTS.md"
    else
        cat << 'EOF'
# AGENTS.md

Project instructions for OpenAI Codex CLI.

## Project Overview

gopher-ai is a Go-focused development toolkit distributed as both Claude Code plugins and Codex plugins. Each plugin bundles related skills that activate automatically or can be invoked explicitly.

## Plugins

| Plugin | Description | Skills |
|--------|-------------|--------|
| `go-workflow` | Issue-to-PR workflow automation | start-issue, create-worktree, commit, create-pr, ship, remove-worktree, prune-worktree, address-review |
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

This repo includes `.agents/plugins/marketplace.json` which Codex reads on startup. When you clone this repo and run Codex inside it, all plugins are discovered automatically.

Use `/plugins` to browse available plugins.

To add these plugins to another repo:

```bash
./scripts/install-codex.sh --repo /path/to/your-repo
```

### Global (Personal) Use

For Codex, "global" means installing plugins through the public Codex plugin CLI so they load in every session, regardless of the working directory.

```bash
./scripts/install-codex.sh --user
```

`--user` registers or upgrades the gopher-ai marketplace and runs `codex plugin add` for each Codex-capable plugin. Codex owns config updates and versioned cache publication.

After all Codex sessions have exited, stale version roots can be removed explicitly:

```bash
./scripts/install-codex.sh --prune-cache
```

Do not prune while a Codex session is active. Restart Codex after installation and use `/plugins` to verify.

## Architecture

```
.agents/plugins/
  marketplace.json       # Codex plugin discovery

.claude-plugin/
  marketplace.json       # Claude Code plugin discovery

plugins/
  <plugin-name>/
    .claude-plugin/
      plugin.json        # Claude Code manifest
    .codex-plugin/
      plugin.json        # Codex manifest
    commands/            # Claude Code slash commands
    skills/              # Skills shared by both platforms
    agents/              # Claude Code agent definitions
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Git with worktree support
- `golangci-lint` (optional, for lint checks)
- `jq` for `./scripts/install-codex.sh`

## Links

- [Gopher Guides](https://gopherguides.com) - Official Go training
- [GitHub Repository](https://github.com/gopherguides/gopher-ai)
EOF
    fi
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
                    if [[ -d "${skill_dir}references" ]]; then
                        cp -R "${skill_dir}references" "$ext_dir/skills/$skill_name/"
                    fi
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

        copy_gemini_runtime_assets "$plugin_dir" "$ext_dir"

        if [[ -d "${plugin_dir}commands/" ]]; then
            for cmd_file in "${plugin_dir}commands/"*.md; do
                if [[ -f "$cmd_file" ]]; then
                    cmd_name=$(basename "$cmd_file" .md)
                    convert_command_to_toml "$cmd_file" "$cmd_name" > "$ext_dir/commands/${cmd_name}.toml"
                fi
            done
        fi

        rewrite_gemini_plugin_paths "$ext_dir" "gopher-ai-$plugin_name"
    done

    "$ROOT_DIR/scripts/validate-gemini-extensions.sh" "$gemini_dir"

    echo "  Done: $gemini_dir"
}

copy_gemini_runtime_assets() {
    local plugin_dir="$1"
    local ext_dir="$2"
    local runtime_dir

    for runtime_dir in scripts lib templates references prompts schemas assets; do
        if [[ -d "${plugin_dir}${runtime_dir}" ]]; then
            cp -R "${plugin_dir}${runtime_dir}" "$ext_dir/"
        fi
    done
}

rewrite_gemini_plugin_paths() {
    local ext_dir="$1"
    local extension_name="$2"
    local gemini_root="\$HOME/.gemini/extensions/$extension_name"
    local file
    local content

    while IFS= read -r -d '' file; do
        if ! grep -qE '\$\{?CLAUDE_PLUGIN_ROOT\}?' "$file" 2>/dev/null; then
            continue
        fi

        content=$(cat "$file"; printf '\037')
        content=${content%$'\037'}
        content=${content//\$\{CLAUDE_PLUGIN_ROOT:-\}/$gemini_root}
        content=${content//\$\{CLAUDE_PLUGIN_ROOT\}/$gemini_root}
        content=${content//\$CLAUDE_PLUGIN_ROOT/$gemini_root}
        printf '%s' "$content" > "$file"
    done < <(find "$ext_dir" -type f -print0)
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
    local in_frontmatter=false
    local frontmatter=""
    local body=""

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

    description=$(extract_frontmatter_value "$frontmatter" "description")
    description=$(strip_wrapping_quotes "$description")
    description=$(toml_escape_basic_string "$description")
    body=$(extract_markdown_body "$cmd_file")
    body=${body//\$ARGUMENTS/\{\{args\}\}}
    body=$(convert_gemini_prompt_body "$body")

    cat << EOF
# Generated from $cmd_name.md
# gopher-ai v$VERSION
description = "$description"
EOF

    emit_toml_multiline_string "prompt" "$body"
}

extract_frontmatter_value() {
    local frontmatter="$1"
    local key="$2"

    awk -v key="$key" '
        index($0, key ":") == 1 {
            sub("^[^:]*:[[:space:]]*", "")
            print
            exit
        }
    ' <<< "$frontmatter"
}

strip_wrapping_quotes() {
    local value="$1"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
    fi

    printf '%s' "$value"
}

toml_escape_basic_string() {
    local value="$1"

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}

    printf '%s' "$value"
}

extract_markdown_body() {
    local file="$1"

    awk '
        /^---$/ {
            delimiters++
            if (delimiters == 2) {
                body = 1
                next
            }
        }
        body { print }
    ' "$file"
}

emit_toml_multiline_string() {
    local key="$1"
    local value="$2"

    if [[ "$value" != *"'''"* ]]; then
        printf "%s = '''\n%s\n'''\n" "$key" "$value"
        return
    fi

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    printf '%s = """\n%s\n"""\n' "$key" "$value"
}

convert_gemini_prompt_body() {
    local value="$1"

    awk '
        function convert_inline(line,    out, i, c, cmd, escaped) {
            out = ""
            i = 1

            while (i <= length(line)) {
                c = substr(line, i, 1)
                if (c == "!" && substr(line, i + 1, 1) == "`") {
                    i += 2
                    cmd = ""
                    escaped = 0

                    while (i <= length(line)) {
                        c = substr(line, i, 1)
                        if (escaped) {
                            if (c == "`") {
                                cmd = cmd c
                            } else {
                                cmd = cmd "\\" c
                            }
                            escaped = 0
                        } else if (c == "\\") {
                            escaped = 1
                        } else if (c == "`") {
                            break
                        } else {
                            cmd = cmd c
                        }
                        i++
                    }

                    if (escaped) {
                        cmd = cmd "\\"
                    }
                    out = out "!{" cmd "}"
                    if (i <= length(line) && substr(line, i, 1) == "`") {
                        i++
                    }
                } else {
                    out = out c
                    i++
                }
            }

            return out
        }

        {
            line = convert_inline($0)
            if (line ~ /^![^\[{]/) {
                line = "!{" substr(line, 2) "}"
            }
            print line
        }
    ' <<< "$value"
}

create_archive() {
    local source_dir="$1"
    local archive="$2"
    local archive_tar="${archive%.gz}"
    local member_list
    local tar_owner_args

    member_list=$(mktemp)
    find "$source_dir" -depth \( -name '._*' -o -name '.DS_Store' \) -delete
    TZ=UTC find "$source_dir" -exec touch -t 200001010000 {} +

    if tar --version 2>&1 | grep -q 'GNU tar'; then
        tar_owner_args=(--owner=0 --group=0 --numeric-owner)
    else
        tar_owner_args=(--uid 0 --gid 0 --uname '' --gname '')
    fi

    (
        cd "$DIST_DIR"
        LC_ALL=C find "$(basename "$source_dir")" -print | LC_ALL=C sort > "$member_list"
        tar --format=ustar --no-recursion "${tar_owner_args[@]}" -cf "$archive_tar" -T "$member_list"
    )
    gzip -n -f "$archive_tar"
    rm -f "$member_list"
}

create_archives() {
    echo ""
    echo "Creating distribution archives..."
    echo "----------------------------------"

    if [[ -d "$DIST_DIR/codex" ]]; then
        create_archive "$DIST_DIR/codex" "$DIST_DIR/gopher-ai-codex-plugins-v${VERSION}.tar.gz"
        echo "  - Created: gopher-ai-codex-plugins-v${VERSION}.tar.gz"
    fi

    if [[ -d "$DIST_DIR/gemini" ]]; then
        create_archive "$DIST_DIR/gemini" "$DIST_DIR/gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
        echo "  - Created: gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
    fi
}

print_summary() {
    echo ""
    echo "======================================================="
    echo "Build complete!"
    echo ""
    echo "Distribution structure:"
    echo ""
    if command -v tree &> /dev/null; then
        tree -L 3 "$DIST_DIR" 2>/dev/null || true
    else
        # Avoid SIGPIPE from head closing early with set -o pipefail active
        find "$DIST_DIR" -type f 2>/dev/null | head -30 || true
    fi
    echo ""
    echo "Installation instructions:"
    echo ""
    echo "  Codex CLI (repo-level plugins):"
    echo "    ./scripts/install-codex.sh --repo /path/to/your-repo"
    echo ""
    echo "  Codex CLI (clean up legacy ~/.codex/skills/ entries):"
    echo "    ./scripts/install-codex.sh --cleanup"
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
