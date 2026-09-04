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
  'selected the skill implicitly' \
  'activating request' \
  'neither an explicit argument' \
  'skip every' \
  '`setup-loop.sh`' \
  '`.local/state/*.loop.local.json`' \
  '`<done>...</done>`' \
  'within the current invocation' \
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
CASE_FILE="$FIXTURE_ROOT/case.md"
MUTATING_OPTION_FILE="$FIXTURE_ROOT/mutating-option.md"
OUTPUT_LIMIT_FILE="$FIXTURE_ROOT/output-limit.md"
CONTROL_FLOW_FILE="$FIXTURE_ROOT/control-flow.md"
FAILED_EXECUTION_FILE="$FIXTURE_ROOT/failed-execution.md"
HEREDOC_FILE="$FIXTURE_ROOT/heredoc.md"
UNQUOTED_HEREDOC_FILE="$FIXTURE_ROOT/unquoted-heredoc.md"
READ_WRITE_REDIRECTION_FILE="$FIXTURE_ROOT/read-write-redirection.md"
SEMANTIC_REVIEW_FILE="$FIXTURE_ROOT/semantic-review.md"
ZSH_EXECUTION_FILE="$FIXTURE_ROOT/zsh-execution.md"
EXECUTABLE_PATH_FILE="$FIXTURE_ROOT/executable-path.md"
PATH_ASSIGNMENT_FILE="$FIXTURE_ROOT/path-assignment.md"
PATH_INLINE_FILE="$FIXTURE_ROOT/path-inline.md"
PATH_EXPORT_FILE="$FIXTURE_ROOT/path-export.md"
PRINTF_PATH_FILE="$FIXTURE_ROOT/printf-path.md"
RED_MARKER="$FIXTURE_ROOT/red-command-ran"
UNKNOWN_MARKER="$FIXTURE_ROOT/unknown-command-ran"
COMMAND_MARKER="$FIXTURE_ROOT/command-ran"
CASE_MARKER="$FIXTURE_ROOT/case-marker"
MUTATING_DIR="$FIXTURE_ROOT/mutating-options"
MALICIOUS_BIN="$FIXTURE_ROOT/malicious-bin"
PATH_MARKER="$FIXTURE_ROOT/path-command-ran"
HEREDOC_MARKER="$FIXTURE_ROOT/heredoc-command-ran"
READ_WRITE_MARKER="$FIXTURE_ROOT/read-write-redirection-ran"
ZSH_MARKER="$FIXTURE_ROOT/zsh-command-ran"

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
printf '%s\n' 'left>right'
printf '%s\n' '$(rm -rf /)'
```
EOF

printf '%s\n' keep > "$CASE_MARKER"
cat > "$CASE_FILE" <<EOF
\`\`\`bash
case keep in keep) rm -f "$CASE_MARKER" ;; esac
\`\`\`
EOF

mkdir -p "$MUTATING_DIR"
printf '%s\n' original > "$MUTATING_DIR/sed-target"
cat > "$MUTATING_OPTION_FILE" <<EOF
\`\`\`bash
sort -o "$MUTATING_DIR/sort-output" /dev/null
diff --output="$MUTATING_DIR/diff-output" /dev/null /dev/null
mktemp "$MUTATING_DIR/mktemp.XXXXXX"
rg --pre 'touch "$MUTATING_DIR/rg-output"' pattern /dev/null
sed -i.bak 's/original/changed/' "$MUTATING_DIR/sed-target"
\`\`\`
EOF

cat > "$OUTPUT_LIMIT_FILE" <<'EOF'
```bash
cat /dev/zero
```
EOF

cat > "$CONTROL_FLOW_FILE" <<'EOF'
```bash
if true; then
  printf '%s\n' valid
fi
while false; do
  printf '%s\n' unreachable
done
```
EOF

cat > "$FAILED_EXECUTION_FILE" <<'EOF'
```bash
printf '%s\n' codex-validator-sensitive-output
false
```
EOF

cat > "$HEREDOC_FILE" <<'MARKDOWN'
```bash
cat <<'EOF'
rm -rf /
printf '%s\n' $UNDEFINED
EOF
```
MARKDOWN

cat > "$UNQUOTED_HEREDOC_FILE" <<EOF
\`\`\`sh
cat <<PAYLOAD
\$(touch "$HEREDOC_MARKER")
PAYLOAD
\`\`\`
EOF

cat > "$READ_WRITE_REDIRECTION_FILE" <<EOF
\`\`\`sh
cat <> "$READ_WRITE_MARKER"
\`\`\`
EOF

cat > "$SEMANTIC_REVIEW_FILE" <<'EOF'
```bash
DEFINED=value
printf '%s\n' "$DEFINED"
printf '%s\n' FOO=value
printf '%s\n' "$FOO"
export DECLARED=value
printf '%s\n' "$DECLARED"
printf '%s\n' $UNDEFINED
printf '%s\n' "$(printf '%s' "$HOME")"
curl -s https://example.invalid | jq .
gh issue list | head -n 1
```
EOF

cat > "$ZSH_EXECUTION_FILE" <<EOF
\`\`\`zsh
printf '%s\n' /dev/null(e:'touch "$ZSH_MARKER"':)
\`\`\`
EOF

mkdir -p "$MALICIOUS_BIN"
cat > "$MALICIOUS_BIN/cat" <<EOF
#!/bin/sh
printf '%s\n' ran > "$PATH_MARKER"
EOF
chmod +x "$MALICIOUS_BIN/cat"

cat > "$EXECUTABLE_PATH_FILE" <<EOF
\`\`\`sh
"$MALICIOUS_BIN/cat"
\`\`\`
EOF

cat > "$PATH_ASSIGNMENT_FILE" <<EOF
\`\`\`sh
PATH="$MALICIOUS_BIN:$PATH"
cat /dev/null
\`\`\`
EOF

cat > "$PATH_INLINE_FILE" <<EOF
\`\`\`sh
PATH="$MALICIOUS_BIN:$PATH" cat /dev/null
\`\`\`
EOF

cat > "$PATH_EXPORT_FILE" <<EOF
\`\`\`sh
export PATH="$MALICIOUS_BIN:$PATH"
cat /dev/null
\`\`\`
EOF

cat > "$PRINTF_PATH_FILE" <<EOF
\`\`\`bash
printf -v PATH '%s' "$MALICIOUS_BIN:$PATH"
cat /dev/null
\`\`\`
EOF

cp "$VALID_FILE" "$FIXTURE_ROOT/plugins/example/commands/valid.md"
cp "$VALID_FILE" "$FIXTURE_ROOT/plugins/example/skills/example/SKILL.md"

FILE_JSON_AFTER=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" valid.md --json)
FILE_JSON_BEFORE=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json valid.md)
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

DIRECTORY_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json plugins/example)
DEFAULT_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json)
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

DEFAULT_OUTPUT=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR")
printf '%s\n' "$DEFAULT_OUTPUT" | matches '^## Validation Report$' || fail "no-argument validation did not render a report"

set +e
INVALID_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json invalid.md)
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

RED_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json red.md)
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

UNKNOWN_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json unknown.md)
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

COMMAND_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json command.md)
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

QUOTED_OPERATOR_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json quoted-operator.md)
python3 - "$QUOTED_OPERATOR_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert not any(
    finding["layer"] == "classification"
    for finding in report["findings"]
)
PY

CASE_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json case.md)
[ -e "$CASE_MARKER" ] || fail "case-arm command bypass removed its marker"
python3 - "$CASE_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert any(
    finding["layer"] == "classification"
    and "Unknown command classified conservatively: compound command" in finding["finding"]
    for finding in report["findings"]
)
PY

MUTATING_OPTION_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json mutating-option.md)
[ ! -e "$MUTATING_DIR/sort-output" ] || fail "sort -o was executed"
[ ! -e "$MUTATING_DIR/diff-output" ] || fail "diff --output was executed"
[ ! -e "$MUTATING_DIR/rg-output" ] || fail "rg --pre was executed"
[ ! -e "$MUTATING_DIR/sed-target.bak" ] || fail "sed -i was executed"
[ "$(cat "$MUTATING_DIR/sed-target")" = original ] || fail "sed mutated its target"
if compgen -G "$MUTATING_DIR/mktemp.*" >/dev/null; then
  fail "mktemp with an explicit path was executed"
fi
python3 - "$MUTATING_OPTION_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert not any(
    finding["layer"] == "execution"
    for finding in report["findings"]
)
PY

OUTPUT_LIMIT_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json output-limit.md)
python3 - "$OUTPUT_LIMIT_JSON" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert any(
    finding["layer"] == "execution"
    and finding["severity"] == "warning"
    and "64 KiB output limit" in finding["finding"]
    for finding in report["findings"]
)
PY

CONTROL_FLOW_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json control-flow.md)
FAILED_EXECUTION_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json failed-execution.md)
python3 - "$CONTROL_FLOW_JSON" "$FAILED_EXECUTION_JSON" <<'PY'
import json
import sys

control_flow = json.loads(sys.argv[1])
failed_execution = json.loads(sys.argv[2])
assert not any(
    finding["layer"] == "classification"
    for finding in control_flow["findings"]
)
assert any(
    finding["layer"] == "execution"
    and "failed with status 1" in finding["finding"]
    for finding in failed_execution["findings"]
)
assert "codex-validator-sensitive-output" not in sys.argv[2]
PY

HEREDOC_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json heredoc.md)
UNQUOTED_HEREDOC_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json unquoted-heredoc.md)
READ_WRITE_REDIRECTION_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json read-write-redirection.md)
SEMANTIC_REVIEW_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json semantic-review.md)
ZSH_EXECUTION_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json zsh-execution.md)
[ ! -e "$HEREDOC_MARKER" ] || fail "unquoted heredoc command substitution was executed"
[ ! -e "$READ_WRITE_MARKER" ] || fail "read-write redirection was executed"
[ ! -e "$ZSH_MARKER" ] || fail "zsh expansion was executed"
python3 - "$HEREDOC_JSON" "$UNQUOTED_HEREDOC_JSON" "$READ_WRITE_REDIRECTION_JSON" "$SEMANTIC_REVIEW_JSON" "$ZSH_EXECUTION_JSON" <<'PY'
import json
import sys

heredoc = json.loads(sys.argv[1])
unquoted_heredoc = json.loads(sys.argv[2])
read_write_redirection = json.loads(sys.argv[3])
semantic = json.loads(sys.argv[4])
zsh_execution = json.loads(sys.argv[5])
assert not any(
    finding["layer"] in {"classification", "review"}
    for finding in heredoc["findings"]
)
assert any(
    finding["layer"] == "classification" and "command substitution" in finding["finding"]
    for finding in unquoted_heredoc["findings"]
)
assert any(
    finding["layer"] == "classification" and "output redirection" in finding["finding"]
    for finding in read_write_redirection["findings"]
)
messages = [finding["finding"] for finding in semantic["findings"]]
assert "Unquoted variable expansion may split or glob: UNDEFINED" in messages
assert "Variables are used before definition or documentation: FOO, UNDEFINED" in messages
assert "Variables are used before definition or documentation: DEFINED" not in messages
assert not any("used before definition" in message and "DECLARED" in message for message in messages)
assert any("without HTTP failure checking" in message for message in messages)
assert any("piped to jq without pipeline error handling" in message for message in messages)
assert any("human-readable output" in message for message in messages)
assert any("first-line output" in message for message in messages)
assert any(
    finding["layer"] == "execution" and "zsh blocks are syntax-check only" in finding["finding"]
    for finding in zsh_execution["findings"]
)
PY

EXECUTABLE_PATH_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json executable-path.md)
PATH_ASSIGNMENT_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json path-assignment.md)
PATH_INLINE_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json path-inline.md)
PATH_EXPORT_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json path-export.md)
PRINTF_PATH_JSON=$(cd "$FIXTURE_ROOT" && python3 "$VALIDATOR" --json printf-path.md)
[ ! -e "$PATH_MARKER" ] || fail "untrusted executable path or PATH mutation was executed"
python3 - "$EXECUTABLE_PATH_JSON" "$PATH_ASSIGNMENT_JSON" "$PATH_INLINE_JSON" "$PATH_EXPORT_JSON" "$PRINTF_PATH_JSON" <<'PY'
import json
import sys

reports = [json.loads(value) for value in sys.argv[1:]]
for report in reports[:3] + reports[4:]:
    assert any(
        finding["layer"] == "classification"
        and finding["severity"] == "warning"
        and "Unknown command classified conservatively" in finding["finding"]
        for finding in report["findings"]
    )
assert not any(
    finding["layer"] == "execution"
    for finding in reports[3]["findings"]
)
PY

printf 'Go-dev Codex skill tests passed.\n'
