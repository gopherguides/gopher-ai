#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/llm-tools"
ADAPTER="$PLUGIN_DIR/lib/codex-command-adapter.md"
CAPABILITIES="$ROOT_DIR/docs/platform-capabilities.json"
SECOND_OPINION="$PLUGIN_DIR/skills/second-opinion/SKILL.md"
OLLAMA_SKILL="$PLUGIN_DIR/skills/ollama/SKILL.md"
PROVIDER_SKILLS=(gemini ollama)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local text="$2"

  awk -v text="$text" 'index($0, text) { found = 1; exit } END { exit found ? 0 : 1 }' "$file" ||
    fail "${file#"$ROOT_DIR/"} is missing: $text"
}

frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && /^---$/ { exit }
    NR > 1 { print }
  ' "$1"
}

matches() {
  local pattern="$1"

  awk -v pattern="$pattern" '$0 ~ pattern { found = 1; exit } END { exit found ? 0 : 1 }'
}

section_text() {
  local file="$1"
  local start="$2"
  local stop="$3"

  awk -v start="$start" -v stop="$stop" '
    $0 == start { section = 1; next }
    section && $0 == stop { exit }
    section { print }
  ' "$file"
}

jq -e '(.commands // []) == []' "$PLUGIN_DIR/.codex-plugin/plugin.json" >/dev/null ||
  fail "llm-tools Codex manifest allows legacy command migration"

[ -f "$ADAPTER" ] || fail "missing shared Codex command adapter"

for skill_name in "${PROVIDER_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  command_file="$PLUGIN_DIR/commands/$skill_name.md"
  policy_file="$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml"

  [ -f "$skill_file" ] || fail "missing skill router: plugins/llm-tools/skills/$skill_name/SKILL.md"
  [ -f "$command_file" ] || fail "missing command body: plugins/llm-tools/commands/$skill_name.md"
  [ -f "$policy_file" ] || fail "$skill_name is missing agents/openai.yaml"

  metadata=$(frontmatter "$skill_file") || fail "$skill_name has invalid frontmatter"
  printf '%s\n' "$metadata" | matches "^name: $skill_name$" || fail "$skill_name has the wrong frontmatter name"
  printf '%s\n' "$metadata" | matches '^description: .+' || fail "$skill_name is missing a description"
  printf '%s\n' "$metadata" | matches '^disable-model-invocation: true$' || fail "$skill_name is not explicit-only"
  matches '^  allow_implicit_invocation: false$' < "$policy_file" || fail "$skill_name policy allows implicit invocation"

  assert_contains "$skill_file" '## Plugin Resource Resolution'
  assert_contains "$skill_file" 'directory containing the absolute selected'
  assert_contains "$skill_file" 'then ascend two directories'
  assert_contains "$skill_file" '<PLUGIN_ROOT>/lib/codex-command-adapter.md'
  assert_contains "$skill_file" "<PLUGIN_ROOT>/commands/$skill_name.md"
  assert_contains "$skill_file" 'Read both files completely'
done

for contract in \
  'SKILL_ARGS' \
  'explicit confirmation' \
  'Google Gemini' \
  "\$llm-tools:gemini" \
  "\$llm-tools:ollama" \
  'Never recommend a Claude Code slash command' \
  'llm_tools_run_provider()'; do
  assert_contains "$ADAPTER" "$contract"
done

for contract in \
  'OLLAMA_HOST' \
  'http://127.0.0.1:11434' \
  '127.0.0.0/8' \
  '::1' \
  'configured destination' \
  'redact any credentials' \
  'Obtain explicit confirmation before sending the prompt or any context.'; do
  assert_contains "$ADAPTER" "$contract"
done

if frontmatter "$OLLAMA_SKILL" | matches 'keeping prompt data on the machine'; then
  fail "Ollama skill description makes an unconditional local-only claim"
fi
frontmatter "$OLLAMA_SKILL" | matches 'configured Ollama endpoint' ||
  fail "Ollama skill description omits endpoint-aware privacy"

GEMINI_SECTION=$(section_text "$SECOND_OPINION" '## Gemini CLI' '## Codex')
CODEX_SECTION=$(section_text "$SECOND_OPINION" '## Codex' '## Claude Code')
CLAUDE_SECTION=$(section_text "$SECOND_OPINION" '## Claude Code' '## When NOT to Suggest')

for command in ollama llm-compare; do
  printf '%s\n' "$GEMINI_SECTION" | matches "(^|[[:space:]\`])/$command([[:space:]\`]|$)" ||
    fail "Gemini second-opinion guidance omits /$command"
done
printf '%s\n' "$GEMINI_SECTION" | matches '/gopher-ai-llm-tools[.]ollama' ||
  fail "Gemini second-opinion guidance omits the extension conflict route"
if printf '%s\n' "$GEMINI_SECTION" | matches '[$]llm-tools:|(^|[[:space:]`])/codex|gopher-ai-llm-tools[.]codex'; then
  fail "Gemini second-opinion guidance suggests another surface's command"
fi

printf '%s\n' "$CODEX_SECTION" | matches '[$]llm-tools:gemini' || fail "Codex second-opinion guidance omits Gemini"
printf '%s\n' "$CODEX_SECTION" | matches '[$]llm-tools:ollama' || fail "Codex second-opinion guidance omits Ollama"
printf '%s\n' "$CODEX_SECTION" | matches 'configured Ollama endpoint' || fail "Codex second-opinion guidance omits endpoint-aware privacy"
if printf '%s\n' "$CODEX_SECTION" | matches 'keeps the prompt on the user.s machine'; then
  fail "Codex second-opinion guidance makes an unconditional local-only claim"
fi
if printf '%s\n' "$CODEX_SECTION" | matches '(^|[[:space:]`])/'; then
  fail "Codex second-opinion guidance suggests a Claude Code slash command"
fi
if printf '%s\n' "$CODEX_SECTION" | matches 'codex@openai-codex|/codex:'; then
  fail "Codex second-opinion guidance exposes Claude-only official plugin routing"
fi
printf '%s\n' "$CLAUDE_SECTION" | matches 'codex@openai-codex' || fail "Claude guidance lost official Codex plugin routing"
printf '%s\n' "$CLAUDE_SECTION" | matches '/codex:review' || fail "Claude guidance lost official review command"

for skill_name in "${PROVIDER_SKILLS[@]}"; do
  jq -e --arg id "llm-tools.$skill_name" --arg name "llm-tools:$skill_name" '
    .capabilities[]
    | select(.id == $id)
    | .platforms.codex == {"disposition": "skill", "name": $name}
  ' "$CAPABILITIES" >/dev/null || fail "$skill_name is not a declared Codex capability"
done

jq -e '
  .capabilities[]
  | select(.id == "llm-tools.ollama")
  | .summary
  | contains("configured Ollama endpoint")
' "$CAPABILITIES" >/dev/null || fail "Ollama capability summary omits endpoint-aware privacy"

for doc in "$ROOT_DIR/README.md" "$PLUGIN_DIR/README.md"; do
  assert_contains "$doc" 'OLLAMA_HOST'
done

for unsupported in cancel-loop codex convert llm-compare review-loop; do
  jq -e --arg id "llm-tools.$unsupported" '
    .capabilities[]
    | select(.id == $id)
    | .platforms.codex.disposition == "unsupported"
  ' "$CAPABILITIES" >/dev/null || fail "$unsupported must remain explicitly unsupported on Codex"
done

RUNNER_FILE=$(mktemp "${TMPDIR:-/tmp}/llm-tools-provider-runner.XXXXXX")
awk '
  /^## Provider Runner$/ { section = 1; next }
  section && /^```bash$/ { block = 1; next }
  block && /^```$/ { exit }
  block { print }
' "$ADAPTER" > "$RUNNER_FILE"

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/llm-tools-codex-skills.XXXXXX")
trap 'rm -rf "$TEST_ROOT" "$RUNNER_FILE"' EXIT
FAKE_BIN="$TEST_ROOT/bin"
ROUTE_LOG="$TEST_ROOT/route.log"
mkdir -p "$FAKE_BIN"

for provider in gemini ollama; do
  provider_path="$FAKE_BIN/$provider"
  {
    printf '%s\n' "printf 'provider=%s\\n' '$provider' >> \"\$LLM_TOOLS_ROUTE_LOG\""
    printf '%s\n' "for arg in \"\$@\"; do printf 'arg=%s\\n' \"\$arg\" >> \"\$LLM_TOOLS_ROUTE_LOG\"; done"
  } > "$provider_path"
  chmod +x "$provider_path"
done

PATH="$FAKE_BIN:/usr/bin:/bin" LLM_TOOLS_ROUTE_LOG="$ROUTE_LOG" bash -c '
  set -euo pipefail
  source "$1"
  llm_tools_run_provider gemini "" "review the auth boundary"
' bash "$RUNNER_FILE"

cat > "$TEST_ROOT/expected-gemini" <<'EOF'
provider=gemini
arg=review the auth boundary
EOF
cmp -s "$TEST_ROOT/expected-gemini" "$ROUTE_LOG" || fail "Gemini routing changed or reached a real provider"

: > "$ROUTE_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" LLM_TOOLS_ROUTE_LOG="$ROUTE_LOG" bash -c '
  set -euo pipefail
  source "$1"
  llm_tools_run_provider ollama "qwen3-coder:latest" "review the auth boundary"
' bash "$RUNNER_FILE"

cat > "$TEST_ROOT/expected-ollama" <<'EOF'
provider=ollama
arg=run
arg=qwen3-coder:latest
arg=review the auth boundary
EOF
cmp -s "$TEST_ROOT/expected-ollama" "$ROUTE_LOG" || fail "Ollama routing changed or reached a real provider"

if PATH="$FAKE_BIN:/usr/bin:/bin" LLM_TOOLS_ROUTE_LOG="$ROUTE_LOG" bash -c '
  set -euo pipefail
  source "$1"
  llm_tools_run_provider codex "" "do not run"
' bash "$RUNNER_FILE" 2>/dev/null; then
  fail "unsupported Codex provider route was accepted"
fi

printf 'llm-tools Codex skill tests passed.\n'
