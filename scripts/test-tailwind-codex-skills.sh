#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/tailwind"
ADAPTER="$PLUGIN_DIR/lib/codex-command-adapter.md"
WORKFLOW_SKILLS=(audit init migrate optimize)
EXPLICIT_SKILLS=(init migrate)
DISCOVERABLE_SKILLS=(audit optimize)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && /^---$/ { exit }
    NR > 1 { print }
  ' "$1"
}

assert_contains() {
  local file="$1"
  local text="$2"

  awk -v text="$text" 'index($0, text) { found = 1; exit } END { exit found ? 0 : 1 }' "$file" ||
    fail "${file#"$ROOT_DIR/"} is missing: $text"
}

matches() {
  local pattern="$1"

  awk -v pattern="$pattern" '$0 ~ pattern { found = 1; exit } END { exit found ? 0 : 1 }'
}

for skill_name in "${WORKFLOW_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  command_file="$PLUGIN_DIR/commands/$skill_name.md"
  [ -f "$skill_file" ] || fail "missing skill router: plugins/tailwind/skills/$skill_name/SKILL.md"
  [ -f "$command_file" ] || fail "missing command body: plugins/tailwind/commands/$skill_name.md"

  metadata=$(frontmatter "$skill_file") || fail "$skill_name has invalid frontmatter"
  printf '%s\n' "$metadata" | matches "^name: $skill_name$" || fail "$skill_name has the wrong frontmatter name"
  printf '%s\n' "$metadata" | matches '^description: .+' || fail "$skill_name is missing a description"
  assert_contains "$skill_file" '## Plugin Resource Resolution'
  assert_contains "$skill_file" 'directory containing the absolute selected'
  assert_contains "$skill_file" 'then ascend two directories'
  assert_contains "$skill_file" '<PLUGIN_ROOT>/lib/codex-command-adapter.md'
  assert_contains "$skill_file" "<PLUGIN_ROOT>/commands/$skill_name.md"
  assert_contains "$skill_file" 'Read both files completely'
done

for skill_name in "${EXPLICIT_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  policy_file="$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml"
  frontmatter "$skill_file" | matches '^disable-model-invocation: true$' || fail "$skill_name is not explicit-only"
  [ -f "$policy_file" ] || fail "$skill_name is missing agents/openai.yaml"
  matches '^  allow_implicit_invocation: false$' < "$policy_file" || fail "$skill_name policy allows implicit invocation"
done

for skill_name in "${DISCOVERABLE_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  if frontmatter "$skill_file" | matches '^disable-model-invocation:'; then
    fail "$skill_name must remain auto-discoverable"
  fi
  [ ! -e "$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml" ] || fail "$skill_name has an explicit-only policy"
done

[ -f "$ADAPTER" ] || fail "missing shared Codex command adapter"
for contract in \
  'SKILL_ARGS' \
  '$ARGUMENTS' \
  '${CLAUDE_PLUGIN_ROOT}' \
  '$tailwind:<skill-name>' \
  'skip every `Loop Initialization` section' \
  '`setup-loop.sh`' \
  '`<done>...</done>`' \
  'audit and optimize are read-only unless `--fix` is present' \
  'Do not modify project files, install dependencies, or overwrite generated CSS' \
  'MCP tools are supplementary'; do
  assert_contains "$ADAPTER" "$contract"
done

printf 'Tailwind Codex workflow skill tests passed.\n'
