#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
SOURCE_LAUNCHER="$ROOT_DIR/plugins/go-workflow/scripts/tmux-start.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-tmux-start-test.XXXXXX")
FIXTURE_DIR="$TEST_ROOT/plugin/scripts"
FAKE_BIN="$TEST_ROOT/bin"
LAUNCHER="$FIXTURE_DIR/tmux-start.sh"
TMUX_LOG="$TEST_ROOT/tmux.log"
ERRORS=0

trap 'rm -rf "$TEST_ROOT"' EXIT
unset GOPHER_AI_TMUX_ASSISTANT_CMD GOPHER_AI_TMUX_CLAUDE_CMD

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  if [[ "$value" != *"$expected"* ]]; then
    fail "$label (missing '$expected')"
  fi
}

create_fixture() {
  mkdir -p "$FIXTURE_DIR" "$FAKE_BIN" "$TEST_ROOT/tmp"
  cp "$SOURCE_LAUNCHER" "$LAUNCHER"
  chmod +x "$LAUNCHER"

  cat > "$FIXTURE_DIR/worktree-create.sh" <<'EOF'
set -euo pipefail

METADATA_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --metadata-file)
      METADATA_FILE="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

cat > "$METADATA_FILE" <<'METADATA'
ITEM_TITLE	Launch originating assistant
REPO_NAME	gopher-ai
WORKTREE_ABS_PATH	/tmp/issue worktree
BRANCH_NAME	issue-327-launch-originating-assistant
METADATA
EOF
  chmod +x "$FIXTURE_DIR/worktree-create.sh"

  cat > "$FAKE_BIN/gh" <<'EOF'
set -euo pipefail

if [ "${1:-} ${2:-}" = "auth status" ]; then
  exit 0
fi
echo "Unexpected gh invocation: $*" >&2
exit 1
EOF

  cat > "$FAKE_BIN/git" <<'EOF'
set -euo pipefail

if [ "${1:-} ${2:-}" = "rev-parse --is-inside-work-tree" ]; then
  echo true
  exit 0
fi
echo "Unexpected git invocation: $*" >&2
exit 1
EOF

  cat > "$FAKE_BIN/jq" <<'EOF'
exit 0
EOF

  cat > "$FAKE_BIN/sleep" <<'EOF'
exit 0
EOF

  cat > "$FAKE_BIN/tmux" <<'EOF'
set -euo pipefail

printf '%s' "${1:-}" >> "$TMUX_TEST_LOG"
shift || true
for arg in "$@"; do
  printf '\t%s' "$arg" >> "$TMUX_TEST_LOG"
done
printf '\n' >> "$TMUX_TEST_LOG"

case "$(head -n 1 "$TMUX_TEST_LOG" | cut -f1)" in
  list-windows)
    ;;
esac

if [ "$(tail -n 1 "$TMUX_TEST_LOG" | cut -f1)" = "capture-pane" ]; then
  printf '%s\n' "$TMUX_READY_OUTPUT"
fi
EOF

  chmod +x "$FAKE_BIN/gh" "$FAKE_BIN/git" "$FAKE_BIN/jq" "$FAKE_BIN/sleep" "$FAKE_BIN/tmux"
}

run_launcher() {
  local ready_output="$1"
  shift
  : > "$TMUX_LOG"
  PATH="$FAKE_BIN:$PATH" \
    TMUX="test-session" \
    TMUX_TEST_LOG="$TMUX_LOG" \
    TMUX_READY_OUTPUT="$ready_output" \
    TMPDIR="$TEST_ROOT/tmp" \
    /bin/bash "$LAUNCHER" 327 --no-copy-env "$@"
}

send_keys_log() {
  awk -F '\t' '$1 == "send-keys"' "$TMUX_LOG"
}

assert_surface_flow() {
  local label="$1"
  local ready_output="$2"
  local expected_command="$3"
  local expected_invocation="$4"
  shift 4
  local output

  if ! output=$(run_launcher "$ready_output" "$@" 2>&1); then
    fail "$label launch failed: $output"
    return
  fi

  assert_contains "$output" "appears ready." "$label readiness detection"

  local window_name="gopher-ai-issue-327-launch-originating-assistant"
  local launch_marker="GOPHER_AI_ASSISTANT_LAUNCHED_327"
  local launch_command="cd /tmp/issue\\ worktree && printf \"\\n${launch_marker}\\n\" && ${expected_command}"
  local expected_log
  expected_log=$(printf 'send-keys\t-t\t%s\t%s\tEnter\nsend-keys\t-t\t%s\t%s\tEnter' \
    "$window_name" "$launch_command" "$window_name" "$expected_invocation")

  assert_equal "$expected_log" "$(send_keys_log)" "$label exact tmux dispatch"
}

create_fixture

echo "=== tmux-start Surface Tests ==="

assert_surface_flow \
  "default Claude caller" \
  "Welcome to Claude Code" \
  "claude --dangerously-skip-permissions" \
  "/go-workflow:start-issue 327"

assert_surface_flow \
  "explicit Codex caller" \
  "OpenAI Codex" \
  "codex --dangerously-bypass-approvals-and-sandbox" \
  "\$go-workflow:start-issue 327" \
  --surface codex

GOPHER_AI_TMUX_ASSISTANT_CMD="neutral assistant" \
GOPHER_AI_TMUX_CLAUDE_CMD="legacy claude" \
  assert_surface_flow \
    "neutral environment override" \
    "Welcome to Claude Code" \
    "neutral assistant" \
    "/go-workflow:start-issue 327" \
    --surface claude

GOPHER_AI_TMUX_ASSISTANT_CMD="neutral codex" \
GOPHER_AI_TMUX_CLAUDE_CMD="legacy claude" \
  assert_surface_flow \
    "neutral Codex environment override" \
    "OpenAI Codex" \
    "neutral codex" \
    "\$go-workflow:start-issue 327" \
    --surface codex

assert_surface_flow \
  "neutral option precedence" \
  "Welcome to Claude Code" \
  "neutral option" \
  "/go-workflow:start-issue 327" \
  --surface claude \
  --assistant-cmd "neutral option" \
  --claude-cmd "legacy option"

GOPHER_AI_TMUX_CLAUDE_CMD="legacy claude" \
  assert_surface_flow \
    "legacy Claude override" \
    "Welcome to Claude Code" \
    "legacy claude" \
    "/go-workflow:start-issue 327" \
    --surface claude

assert_surface_flow \
  "stable launch marker fallback" \
  "GOPHER_AI_ASSISTANT_LAUNCHED_327" \
  "codex --dangerously-bypass-approvals-and-sandbox" \
  "\$go-workflow:start-issue 327" \
  --surface codex

if invalid_output=$(run_launcher "OpenAI Codex" --surface other 2>&1); then
  fail "invalid surface succeeds unexpectedly"
else
  assert_contains "$invalid_output" "--surface requires claude or codex" "invalid surface error"
fi

assert_option_failure() {
  local label="$1"
  local expected="$2"
  shift 2
  local output

  if output=$(run_launcher "OpenAI Codex" "$@" 2>&1); then
    fail "$label succeeds unexpectedly"
  else
    assert_contains "$output" "$expected" "$label error"
  fi
}

assert_option_failure "missing surface value" "--surface requires claude or codex" --surface
assert_option_failure "missing assistant command" "--assistant-cmd requires a command" --assistant-cmd
assert_option_failure "assistant command followed by option" "--assistant-cmd requires a command" --assistant-cmd --surface codex
assert_option_failure "missing Claude command" "--claude-cmd requires a command" --claude-cmd
assert_option_failure "Claude command followed by option" "--claude-cmd requires a command" --claude-cmd --surface claude

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS tmux-start test(s) failed"
  exit 1
fi

echo "All tmux-start surface tests passed."
