#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/go-dev"
CODEX_MANIFEST="$PLUGIN_DIR/.codex-plugin/plugin.json"
ADAPTER="$PLUGIN_DIR/lib/codex-command-adapter.md"
VALIDATOR="$PLUGIN_DIR/scripts/validate-skills.py"
WORKFLOW_SKILLS=(bench build-fix explain lint-fix profile refactor-clean test-gen verify)
EXPLICIT_SKILLS=(bench build-fix lint-fix profile refactor-clean test-gen verify)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

jq -e '.commands == []' "$CODEX_MANIFEST" >/dev/null || fail "go-dev Codex manifest allows legacy command migration"

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

assert_not_contains() {
  local file="$1"
  local text="$2"

  if awk -v text="$text" 'index($0, text) { found = 1; exit } END { exit found ? 0 : 1 }' "$file"; then
    fail "${file#"$ROOT_DIR/"} unexpectedly contains: $text"
  fi
}

matches() {
  local pattern="$1"

  awk -v pattern="$pattern" '$0 ~ pattern { found = 1; exit } END { exit found ? 0 : 1 }'
}

for skill_name in "${WORKFLOW_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  command_file="$PLUGIN_DIR/commands/$skill_name.md"
  [ -f "$skill_file" ] || fail "missing skill router: plugins/go-dev/skills/$skill_name/SKILL.md"
  [ -f "$command_file" ] || fail "missing command body: plugins/go-dev/commands/$skill_name.md"

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

for skill_name in explain validate-skills; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  if frontmatter "$skill_file" | matches '^disable-model-invocation:'; then
    fail "$skill_name must remain auto-discoverable"
  fi
  [ ! -e "$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml" ] || fail "$skill_name has an explicit-only policy"
done

[ -f "$ADAPTER" ] || fail "missing shared Codex command adapter"
for contract in \
  'SKILL_ARGS' \
  "\$ARGUMENTS" \
  "\${CLAUDE_PLUGIN_ROOT}" \
  'native structured-input capability' \
  'native delegation capability' \
  'Do not require the go-workflow plugin'; do
  assert_contains "$ADAPTER" "$contract"
done

VALIDATE_SKILL="$PLUGIN_DIR/skills/validate-skills/SKILL.md"
VALIDATE_COMMAND="$PLUGIN_DIR/commands/validate-skills.md"
assert_contains "$VALIDATE_SKILL" '<PLUGIN_ROOT>/scripts/validate-skills.py'
assert_contains "$VALIDATE_SKILL" "\$go-dev:validate-skills"
if matches '(^|[[:space:]`])/validate-skills([[:space:]`]|$)' < "$VALIDATE_SKILL"; then
  fail "validate-skills suggests a Claude-only slash command"
fi
assert_contains "$VALIDATE_COMMAND" "\${CLAUDE_PLUGIN_ROOT}/scripts/validate-skills.py"
for reference in classification.md execution.md ai-review.md; do
  assert_contains "$VALIDATE_SKILL" "<PLUGIN_ROOT>/lib/validate-skills/$reference"
  assert_contains "$VALIDATE_COMMAND" "\${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/$reference"
done

[ -x "$VALIDATOR" ] || fail "validate-skills.py is missing or not executable"

TEST_TMP_BASE="${TMPDIR:-/tmp}"
FIXTURE_ROOT=$(mktemp -d "$TEST_TMP_BASE/go-dev-codex-skills.XXXXXX")
mkdir -p "$FIXTURE_ROOT/plugins/example/commands" "$FIXTURE_ROOT/plugins/example/skills/example"

VALID_FILE="$FIXTURE_ROOT/valid.md"
INVALID_FILE="$FIXTURE_ROOT/invalid.md"
RED_FILE="$FIXTURE_ROOT/red.md"
UNKNOWN_FILE="$FIXTURE_ROOT/unknown.md"
COMMAND_FILE="$FIXTURE_ROOT/command.md"
QUOTED_OPERATOR_FILE="$FIXTURE_ROOT/quoted-operator.md"
RED_MARKER="$FIXTURE_ROOT/red-command-ran"
UNKNOWN_MARKER="$FIXTURE_ROOT/unknown-command-ran"
COMMAND_MARKER="$FIXTURE_ROOT/command-ran"

cat > "$VALID_FILE" <<'EOF'
```bash
printf '%s\n' valid
```
EOF

cat > "$INVALID_FILE" <<'EOF'
```bash
if true; then
  printf '%s\n' invalid
```
EOF

cat > "$RED_FILE" <<EOF
\`\`\`bash
rm -f "$FIXTURE_ROOT/not-present"
printf '%s\\n' ran > "$RED_MARKER"
\`\`\`
EOF

cat > "$UNKNOWN_FILE" <<EOF
\`\`\`bash
printf '%s\\n' "\$(touch "$UNKNOWN_MARKER")"
\`\`\`
EOF

cat > "$COMMAND_FILE" <<EOF
\`\`\`bash
command touch "$COMMAND_MARKER"
\`\`\`
EOF

cat > "$QUOTED_OPERATOR_FILE" <<'EOF'
```bash
printf '%s\n' 'left|right'
printf '%s\n' 'left;right'
printf '%s\n' "left&&right"
printf '%s\n' escaped\|value
printf '%s\n' \
  'continued|value'
printf '%s\n' value # ignored | command
```
EOF

cp "$VALID_FILE" "$FIXTURE_ROOT/plugins/example/commands/valid.md"
cp "$VALID_FILE" "$FIXTURE_ROOT/plugins/example/skills/example/SKILL.md"

FILE_JSON_AFTER=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" valid.md --json)
FILE_JSON_BEFORE=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json valid.md)
[ "$FILE_JSON_AFTER" = "$FILE_JSON_BEFORE" ] || fail "--json flag order changes validator output"

python3 - "$FILE_JSON_AFTER" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert set(report) == {"files_scanned", "blocks_found", "findings", "summary"}
assert report["files_scanned"] == 1
assert report["blocks_found"] == 1
assert isinstance(report["findings"], list)
assert set(report["summary"]) == {"errors", "warnings", "info"}
PY

DIRECTORY_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json plugins/example)
DEFAULT_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json)
python3 - "$DIRECTORY_JSON" "$DEFAULT_JSON" <<'PY'
import json
import sys

directory = json.loads(sys.argv[1])
default = json.loads(sys.argv[2])
assert directory["files_scanned"] == 2
assert directory["blocks_found"] == 2
assert default["files_scanned"] == 2
assert default["blocks_found"] == 2
PY

DEFAULT_OUTPUT=$(cd "$FIXTURE_ROOT" && "$VALIDATOR")
printf '%s\n' "$DEFAULT_OUTPUT" | matches '^## Validation Report$' || fail "no-argument validation did not render a report"

set +e
INVALID_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json invalid.md)
INVALID_STATUS=$?
set -e
[ "$INVALID_STATUS" -ne 0 ] || fail "syntax errors do not produce a nonzero exit"
python3 - "$INVALID_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
errors = [finding for finding in report["findings"] if finding["severity"] == "error"]
assert report["summary"]["errors"] >= 1
assert errors[0]["file"] == "invalid.md"
assert errors[0]["start_line"] == 2
assert errors[0]["end_line"] == 3
assert "Markdown line 3" in errors[0]["finding"]
PY

RED_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json red.md)
[ ! -e "$RED_MARKER" ] || fail "RED-tier block was executed"
python3 - "$RED_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert any(
    finding["layer"] == "classification"
    and finding["severity"] == "warning"
    and "RED-tier command" in finding["finding"]
    for finding in report["findings"]
)
PY

UNKNOWN_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json unknown.md)
[ ! -e "$UNKNOWN_MARKER" ] || fail "unknown command was executed"
python3 - "$UNKNOWN_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert any(
    finding["layer"] == "classification"
    and finding["severity"] == "warning"
    and "Unknown command" in finding["finding"]
    for finding in report["findings"]
)
PY

COMMAND_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json command.md)
[ ! -e "$COMMAND_MARKER" ] || fail "command builtin bypass was executed"
python3 - "$COMMAND_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert any(
    finding["layer"] == "classification"
    and finding["severity"] == "warning"
    and "Unknown command classified conservatively: command" in finding["finding"]
    for finding in report["findings"]
)
PY

QUOTED_OPERATOR_JSON=$(cd "$FIXTURE_ROOT" && "$VALIDATOR" --json quoted-operator.md)
python3 - "$QUOTED_OPERATOR_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert not any(
    finding["layer"] == "classification"
    for finding in report["findings"]
)
PY

printf 'Go-dev Codex skill tests passed.\n'
