#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$ROOT_DIR/plugins/go-workflow/skills/cancel-loop"
SKILL_FILE="$SKILL_DIR/SKILL.md"
POLICY_FILE="$SKILL_DIR/agents/openai.yaml"
CAPABILITIES_FILE="$ROOT_DIR/docs/platform-capabilities.json"
MATRIX_FILE="$ROOT_DIR/docs/platform-capabilities.md"
CLEANUP_SCRIPT="$ROOT_DIR/shared/scripts/cleanup-loop.sh"
FIXTURE_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
case "$FIXTURE_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$FIXTURE_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac
FIXTURE_BASE=$(mktemp -d "$FIXTURE_TMP_BASE/gopher-ai-cancel-loop.XXXXXX")

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected='$expected', actual='$actual')"
    FAIL=$((FAIL + 1))
  fi
}

fixture() {
  local name="$1"
  local repo="$FIXTURE_BASE/$name"
  mkdir -p "$repo/.local/state"
  git -C "$repo" init -q
  printf '%s\n' "$repo"
}

echo "=== Cancel Loop Tests ==="

if [ -f "$SKILL_FILE" ]; then
  assert_eq "skill frontmatter declares cancel-loop" "true" \
    "$(awk '
      /^---$/ { delimiters++; next }
      delimiters == 1 && /^name:[[:space:]]+cancel-loop[[:space:]]*$/ { name = 1 }
      delimiters == 1 && /^argument-hint:[[:space:]]+"\[loop-name\]"[[:space:]]*$/ { hint = 1 }
      delimiters == 1 && /^disable-model-invocation:[[:space:]]+true[[:space:]]*$/ { explicit = 1 }
      delimiters == 2 { exit }
      END { print name && hint && explicit ? "true" : "false" }
    ' "$SKILL_FILE")"
  assert_eq "skill uses the portable plugin resource contract" "true" \
    "$(rg -q '## Plugin Resource Resolution' "$SKILL_FILE" &&
       rg -q 'directory containing the absolute selected `SKILL.md` path, then ascend two directories' "$SKILL_FILE" &&
       rg -q 'injected `\$\{CLAUDE_PLUGIN_ROOT\}`' "$SKILL_FILE" && echo true || echo false)"
  assert_eq "skill binds qualified Codex arguments" "true" \
    "$(rg -q 'SKILL_ARGS.*\$go-workflow:cancel-loop' "$SKILL_FILE" &&
       rg -q '<claude-skill-arguments>' "$SKILL_FILE" &&
       rg -q '^\$ARGUMENTS$' "$SKILL_FILE" && echo true || echo false)"
  assert_eq "skill delegates cancellation to the shared helper" "true" \
    "$(rg -Fq '"<PLUGIN_ROOT>/scripts/cleanup-loop.sh" "$SKILL_ARGS"' "$SKILL_FILE" && echo true || echo false)"
  assert_eq "skill documents Codex and Claude invocation separately" "true" \
    "$(rg -Fq 'Codex: `$go-workflow:cancel-loop [loop-name]`' "$SKILL_FILE" &&
       rg -Fq 'Claude Code: `/go-workflow:cancel-loop [loop-name]`' "$SKILL_FILE" && echo true || echo false)"
else
  assert_eq "cancel-loop skill exists" "true" "false"
fi

assert_eq "skill is explicit-only" "true" \
  "$([ -f "$POLICY_FILE" ] && ruby -ryaml -e 'data = YAML.load_file(ARGV[0]); exit(data.dig("policy", "allow_implicit_invocation") == false ? 0 : 1)' "$POLICY_FILE" && echo true || echo false)"
assert_eq "capability inventory exposes the Codex skill" "true" \
  "$(jq -e '
    .capabilities[] |
    select(.id == "go-workflow.cancel-loop") |
    any(.sources[]; .kind == "skill" and .path == "plugins/go-workflow/skills/cancel-loop/SKILL.md") and
    .platforms.codex.disposition == "skill" and
    .platforms.codex.name == "go-workflow:cancel-loop"
  ' "$CAPABILITIES_FILE" >/dev/null && echo true || echo false)"
assert_eq "platform matrix lists the qualified Codex skill" "true" \
  "$(rg -Fq '$go-workflow:cancel-loop' "$MATRIX_FILE" &&
     ! rg -Fq '`cancel-loop` is unsupported ([#332]' "$MATRIX_FILE" && echo true || echo false)"

EMPTY_REPO=$(fixture empty)
EMPTY_OUTPUT=$(cd "$EMPTY_REPO" && bash "$CLEANUP_SCRIPT")
assert_eq "no active loop reports no removal" "No active loops found." "$EMPTY_OUTPUT"
assert_eq "no active loop leaves the state directory empty" "0" \
  "$(fd -d 1 -t f --glob '*.loop.local.json' "$EMPTY_REPO/.local/state" | wc -l | tr -d ' ')"

ACTIVE_REPO=$(fixture active)
ACTIVE_STATE="$ACTIVE_REPO/.local/state/ship.loop.local.json"
printf '%s\n' '{"loop_name":"ship","completion_promise":"SHIPPED"}' > "$ACTIVE_STATE"
ACTIVE_OUTPUT=$(cd "$ACTIVE_REPO" && bash "$CLEANUP_SCRIPT")
assert_eq "active loop reports the removed loop" $'Cancelled loop: ship\nAll active loops cancelled.' "$ACTIVE_OUTPUT"
assert_eq "active loop state is removed" "false" "$([ -e "$ACTIVE_STATE" ] && echo true || echo false)"

NAMED_REPO=$(fixture named)
NAMED_STATE="$NAMED_REPO/.local/state/ship.loop.local.json"
UNRELATED_STATE="$NAMED_REPO/.local/state/start-issue-42.loop.local.json"
printf '%s\n' '{"loop_name":"ship","completion_promise":"SHIPPED"}' > "$NAMED_STATE"
printf '%s\n' '{"loop_name":"start-issue-42","completion_promise":"COMPLETE","marker":"preserve"}' > "$UNRELATED_STATE"
UNRELATED_BEFORE=$(jq -cS . "$UNRELATED_STATE")
NAMED_OUTPUT=$(cd "$NAMED_REPO" && bash "$CLEANUP_SCRIPT" ship)
assert_eq "named loop reports the removed loop" "Loop 'ship' cancelled." "$NAMED_OUTPUT"
assert_eq "named loop state is removed" "false" "$([ -e "$NAMED_STATE" ] && echo true || echo false)"
assert_eq "named cancellation leaves unrelated state unchanged" "$UNRELATED_BEFORE" "$(jq -cS . "$UNRELATED_STATE")"

echo "========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
