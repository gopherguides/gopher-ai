#!/bin/bash
# Exercise e2e-browser.sh and its loop cleanup wiring against a fake chrome-devtools CLI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$ROOT_DIR/shared/scripts/e2e-browser.sh"
LOOP_LIB="$ROOT_DIR/shared/lib/loop-state.sh"
SETUP_LOOP="$ROOT_DIR/shared/scripts/setup-loop.sh"
CLEANUP_SCRIPT="$ROOT_DIR/shared/scripts/cleanup-loop.sh"
STOP_HOOK="$ROOT_DIR/shared/hooks/stop-hook.sh"
TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
TMP_BASE=$(cd "$TMP_BASE" && pwd -P) || exit 1
case "$TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac
WORK=$(mktemp -d "$TMP_BASE/gopher-ai-e2e-browser.XXXXXX")
FAKE_BIN="$WORK/bin"
export FAKE_CDT_ROOT="$WORK/fake"
export E2E_BROWSER_STOP_POLLS=8
export E2E_BROWSER_STOP_INTERVAL=0.05
ORIGINAL_PATH="$PATH"
export PATH="$FAKE_BIN:$PATH"

PASS=0
FAIL=0

cleanup() {
  local pid_file
  for pid_file in "$FAKE_CDT_ROOT"/sessions/*/pid; do
    [ -f "$pid_file" ] || continue
    kill "$(cat "$pid_file")" 2>/dev/null || true
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

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

mkdir -p "$FAKE_BIN" "$FAKE_CDT_ROOT/sessions"
cat > "$FAKE_BIN/chrome-devtools" <<'FAKE'
#!/bin/bash
set -euo pipefail
root="$FAKE_CDT_ROOT"
session=""
args=()
for arg in "$@"; do
  case "$arg" in
    --sessionId=*) session="${arg#--sessionId=}" ;;
    *) args+=("$arg") ;;
  esac
done
cmd="${args[0]:-}"
dir="$root/sessions/${session:-default}"
printf '%s %s\n' "${session:-default}" "${args[*]}" >> "$root/log"

running() {
  [ -f "$dir/pid" ] && kill -0 "$(cat "$dir/pid")" 2>/dev/null
}

launch() {
  mkdir -p "$dir"
  sleep 600 >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$dir/pid"
  printf '%s\n' '[{"id":1,"url":"about:blank"}]' > "$dir/pages"
}

pages_json() {
  jq -c --argjson selected "${1:-0}" '{pages: map(. + {selected: (.id == $selected)})}' "$dir/pages"
}

case "$cmd" in
  start)
    running && kill "$(cat "$dir/pid")"
    launch
    [ ! -e "$root/fail-start" ] || exit 1
    ;;
  status)
    if running; then
      echo "chrome-devtools-mcp daemon is running."
      echo "pid=$(cat "$dir/pid") socket=/tmp/chrome-devtools-mcp-$session-501.sock version=0.0.0"
    else
      echo "chrome-devtools-mcp daemon is not running."
    fi
    ;;
  stop)
    [ ! -e "$root/fail-stop" ] || exit 1
    if running; then
      kill "$(cat "$dir/pid")"
      while kill -0 "$(cat "$dir/pid")" 2>/dev/null; do sleep 0.01; done
    fi
    rm -f "$dir/pid"
    ;;
  *)
    running || launch
    case "$cmd" in
      new_page)
        id=$(jq 'map(.id) | max + 1' "$dir/pages")
        jq --argjson id "$id" --arg url "${args[1]}" '. + [{id: $id, url: $url}]' "$dir/pages" > "$dir/pages.tmp"
        mv "$dir/pages.tmp" "$dir/pages"
        pages_json "$id"
        ;;
      list_pages) pages_json 0 ;;
      *)
        if [ -e "$root/tool-error" ]; then
          echo '[{"type":"text","text":"Error: simulated tool failure"}]'
        else
          echo '{"message":"ok"}'
        fi
        ;;
    esac
    ;;
esac
FAKE
chmod +x "$FAKE_BIN/chrome-devtools"

state_field() {
  jq -r ".$2 | values" "$1"
}

daemon_alive() {
  kill -0 "$1" 2>/dev/null && echo true || echo false
}

succeeds() {
  "$@" >/dev/null 2>&1 && echo true || echo false
}

echo "=== E2E Browser Session Tests ==="

STATE_A="$WORK/runs/a/session.json"
STATE_B="$WORK/runs/b/session.json"

assert_eq "start launches an owned session" "true" "$(succeeds /bin/bash "$HELPER" start "$STATE_A")"
assert_eq "a second run starts an independent session" "true" "$(succeeds /bin/bash "$HELPER" start "$STATE_B")"
PID_A=$(state_field "$STATE_A" daemon_pid)
PID_B=$(state_field "$STATE_B" daemon_pid)
assert_eq "sessions use distinct ids" "false" \
  "$([ "$(state_field "$STATE_A" session)" = "$(state_field "$STATE_B" session)" ] && echo true || echo false)"
assert_eq "state records the marker page" "2" "$(state_field "$STATE_A" marker_id)"
assert_eq "state is private" "600" "$(stat -f '%Lp' "$STATE_A" 2>/dev/null || stat -c '%a' "$STATE_A")"
assert_eq "start refuses to overwrite recorded ownership" "false" "$(succeeds /bin/bash "$HELPER" start "$STATE_A")"

PAGE_ID=$(/bin/bash "$HELPER" call "$STATE_A" new_page "http://localhost:8080/" | jq -r '.pages[] | select(.selected) | .id')
assert_eq "call returns the app page id" "3" "$PAGE_ID"
assert_eq "page-scoped tools run in the owned session" "true" \
  "$(succeeds /bin/bash "$HELPER" call "$STATE_A" take_screenshot "$PAGE_ID" --filePath "$WORK/shot.png")"
assert_eq "callers cannot override the session" "false" \
  "$(succeeds /bin/bash "$HELPER" call "$STATE_A" list_pages --sessionId=other)"
assert_eq "callers cannot run lifecycle commands" "false" "$(succeeds /bin/bash "$HELPER" call "$STATE_A" stop)"
touch "$FAKE_CDT_ROOT/tool-error"
assert_eq "exit-zero tool errors fail the call" "false" \
  "$(succeeds /bin/bash "$HELPER" call "$STATE_A" click "$PAGE_ID" missing-uid)"
rm -f "$FAKE_CDT_ROOT/tool-error"

assert_eq "stop ends the owned session" "true" "$(succeeds /bin/bash "$HELPER" stop "$STATE_A")"
assert_eq "stop terminates the owned daemon" "false" "$(daemon_alive "$PID_A")"
assert_eq "stop marks ownership inactive" "false" "$(state_field "$STATE_A" active)"
assert_eq "stop leaves the other run's daemon alive" "true" "$(daemon_alive "$PID_B")"
assert_eq "the other run still answers calls" "true" "$(succeeds /bin/bash "$HELPER" call "$STATE_B" list_pages)"
assert_eq "repeated stop is a no-op" "true" "$(succeeds /bin/bash "$HELPER" stop "$STATE_A")"
assert_eq "a stopped session is not restarted for evidence" "false" "$(succeeds /bin/bash "$HELPER" call "$STATE_A" list_pages)"
SESSION_A=$(state_field "$STATE_A" session)
assert_eq "a stopped session stays down" "false" \
  "$([ -f "$FAKE_CDT_ROOT/sessions/$SESSION_A/pid" ] && echo true || echo false)"
assert_eq "stop with no recorded state succeeds" "true" "$(succeeds /bin/bash "$HELPER" stop "$WORK/runs/none/session.json")"

kill "$PID_B"
while kill -0 "$PID_B" 2>/dev/null; do sleep 0.01; done
SESSION_B=$(state_field "$STATE_B" session)
assert_eq "a lost session fails the call" "false" "$(succeeds /bin/bash "$HELPER" call "$STATE_B" list_pages)"
assert_eq "a lost session is not reconnected" "false" \
  "$([ -f "$FAKE_CDT_ROOT/sessions/$SESSION_B/pid" ] && kill -0 "$(cat "$FAKE_CDT_ROOT/sessions/$SESSION_B/pid")" 2>/dev/null && echo true || echo false)"
chrome-devtools start --sessionId="$SESSION_B" >/dev/null
REPLACEMENT_PID=$(cat "$FAKE_CDT_ROOT/sessions/$SESSION_B/pid")
assert_eq "a replacement browser is rejected" "false" "$(succeeds /bin/bash "$HELPER" call "$STATE_B" list_pages)"
assert_eq "stop cleans up a replacement under the owned id" "true" "$(succeeds /bin/bash "$HELPER" stop "$STATE_B")"
assert_eq "replacement daemon is gone" "false" "$(daemon_alive "$REPLACEMENT_PID")"

STATE_FAILED_START="$WORK/runs/failed-start/session.json"
touch "$FAKE_CDT_ROOT/fail-start"
assert_eq "failed startup reports failure" "false" "$(succeeds /bin/bash "$HELPER" start "$STATE_FAILED_START")"
rm -f "$FAKE_CDT_ROOT/fail-start"
FAILED_SESSION=$(state_field "$STATE_FAILED_START" session)
assert_eq "failed startup still records ownership" "true" "$([ -n "$FAILED_SESSION" ] && echo true || echo false)"
assert_eq "failed startup stops its partial session" "false" "$(state_field "$STATE_FAILED_START" active)"
assert_eq "failed startup leaves no daemon" "false" \
  "$([ -f "$FAKE_CDT_ROOT/sessions/$FAILED_SESSION/pid" ] && echo true || echo false)"

STATE_NO_CLI="$WORK/runs/no-cli/session.json"
assert_eq "missing CLI fails startup" "false" \
  "$(PATH="/usr/bin:/bin" succeeds /bin/bash "$HELPER" start "$STATE_NO_CLI")"
assert_eq "missing CLI records nothing to clean up" "false" "$([ -e "$STATE_NO_CLI" ] && echo true || echo false)"

STATE_RETRY="$WORK/runs/retry/session.json"
/bin/bash "$HELPER" start "$STATE_RETRY" >/dev/null
PID_RETRY=$(state_field "$STATE_RETRY" daemon_pid)
touch "$FAKE_CDT_ROOT/fail-stop"
assert_eq "failed cleanup reports failure" "false" "$(succeeds /bin/bash "$HELPER" stop "$STATE_RETRY")"
assert_eq "failed cleanup keeps ownership for retry" "true" "$(state_field "$STATE_RETRY" active)"
rm -f "$FAKE_CDT_ROOT/fail-stop"
assert_eq "cleanup retry succeeds" "true" "$(succeeds /bin/bash "$HELPER" stop "$STATE_RETRY")"
assert_eq "cleanup retry stops the daemon" "false" "$(daemon_alive "$PID_RETRY")"

echo "=== Loop Cleanup Wiring Tests ==="

loop_fixture() {
  local name="$1" browser_state="$2"
  local dir="$WORK/loops/$name"
  mkdir -p "$dir/.local/state"
  (
    cd "$dir"
    export CLAUDE_SESSION_ID="$name-session"
    bash "$SETUP_LOOP" "e2e-verify-42" "VERIFIED" >/dev/null
  )
  local state="$dir/.local/state/e2e-verify-42.loop.local.json"
  jq --arg browser "$browser_state" '.components["e2e-verify"].e2e_browser_state = $browser' "$state" > "$state.tmp"
  mv "$state.tmp" "$state"
  printf '%s\n' "$dir"
}

for shell_name in bash zsh; do
  if ! command -v "$shell_name" >/dev/null 2>&1; then
    echo "  SKIP: $shell_name is not installed"
    continue
  fi
  SHELL_BROWSER="$WORK/runs/lib-$shell_name/session.json"
  /bin/bash "$HELPER" start "$SHELL_BROWSER" >/dev/null
  SHELL_PID=$(state_field "$SHELL_BROWSER" daemon_pid)
  SHELL_LOOP=$(loop_fixture "lib-$shell_name" "$SHELL_BROWSER")
  SHELL_STATE="$SHELL_LOOP/.local/state/e2e-verify-42.loop.local.json"
  touch "$FAKE_CDT_ROOT/fail-stop"
  assert_eq "$shell_name cleanup_loop reports failed browser shutdown" "false" \
    "$(succeeds "$shell_name" -c 'source "$1"; cleanup_loop "$2"' _ "$LOOP_LIB" "$SHELL_STATE")"
  assert_eq "$shell_name cleanup_loop keeps loop state for retry" "true" "$([ -f "$SHELL_STATE" ] && echo true || echo false)"
  rm -f "$FAKE_CDT_ROOT/fail-stop"
  assert_eq "$shell_name cleanup_loop retry succeeds" "true" \
    "$(succeeds "$shell_name" -c 'source "$1"; cleanup_loop "$2"' _ "$LOOP_LIB" "$SHELL_STATE")"
  assert_eq "$shell_name cleanup_loop removes loop state" "false" "$([ -f "$SHELL_STATE" ] && echo true || echo false)"
  assert_eq "$shell_name cleanup_loop stops the browser" "false" "$(daemon_alive "$SHELL_PID")"
done

E2E_DOC="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/e2e-test-execution.md"
doc_block() {
  awk -v needle="$1" -v root="$ROOT_DIR/shared" '
    /^```bash$/ { inside = 1; block = ""; next }
    /^```$/ && inside { if (index(block, needle)) { printf "%s", block; exit } inside = 0; next }
    inside { gsub(/<PLUGIN_ROOT>/, root); block = block $0 "\n" }
  ' "$E2E_DOC"
}
START_BLOCK=$(doc_block 'E2E_BROWSER_ROOT=')
STOP_BLOCK=$(doc_block '"e2e_browser_cleanup" "stopped"')
assert_eq "skill documents a startup block" "true" "$([ -n "$START_BLOCK" ] && echo true || echo false)"
assert_eq "skill documents a cleanup block" "true" "$([ -n "$STOP_BLOCK" ] && echo true || echo false)"
BLOCK_LOOP=$(loop_fixture "blocks-bash" "")
BLOCK_STATE="$BLOCK_LOOP/.local/state/e2e-verify-42.loop.local.json"
BLOCK_RESULT=$(
  XDG_STATE_HOME="$WORK/xdg-bash" bash -c '
    source "$1"
    STATE_FILE="$2"
    WORKFLOW_STATE_PATH="[\"components\",\"e2e-verify\"]"
    eval "$3"
    FIRST_STATE="$E2E_BROWSER_STATE"
    eval "$3"
    [ "$E2E_BROWSER_STATE" = "$FIRST_STATE" ] || { echo reentry-started-second-session; exit 1; }
    E2E_RESULT=pass
    eval "$4"
    printf "RESULT:%s %s %s\n" "$E2E_RESULT" "$(jq -r .active "$E2E_BROWSER_STATE")" \
      "$(get_loop_field "$STATE_FILE" e2e_browser_cleanup "$WORKFLOW_STATE_PATH")"
  ' _ "$LOOP_LIB" "$BLOCK_STATE" "$START_BLOCK" "$STOP_BLOCK" 2>/dev/null | sed -n 's/^RESULT://p'
)
assert_eq "bash skill blocks start once, reuse on re-entry, and stop" "pass false stopped" "$BLOCK_RESULT"
BLOCK_LOOP=$(loop_fixture "blocks-fail-bash" "")
BLOCK_STATE="$BLOCK_LOOP/.local/state/e2e-verify-42.loop.local.json"
BLOCK_RESULT=$(
  XDG_STATE_HOME="$WORK/xdg-fail-bash" bash -c '
    source "$1"
    STATE_FILE="$2"
    WORKFLOW_STATE_PATH="[\"components\",\"e2e-verify\"]"
    eval "$3"
    touch "$FAKE_CDT_ROOT/fail-stop"
    E2E_RESULT=pass
    eval "$4"
    rm -f "$FAKE_CDT_ROOT/fail-stop"
    printf "RESULT:%s %s\n" "$E2E_RESULT" "$(get_loop_field "$STATE_FILE" e2e_browser_cleanup "$WORKFLOW_STATE_PATH")"
    source "$1"
    cleanup_loop "$STATE_FILE" >/dev/null
  ' _ "$LOOP_LIB" "$BLOCK_STATE" "$START_BLOCK" "$STOP_BLOCK" 2>/dev/null | sed -n 's/^RESULT://p'
)
assert_eq "bash skill cleanup failure turns a pass into a fail" "fail failed" "$BLOCK_RESULT"

CANCEL_BROWSER="$WORK/runs/cancel/session.json"
/bin/bash "$HELPER" start "$CANCEL_BROWSER" >/dev/null
CANCEL_PID=$(state_field "$CANCEL_BROWSER" daemon_pid)
CANCEL_LOOP=$(loop_fixture cancel "$CANCEL_BROWSER")
CANCEL_STATE="$CANCEL_LOOP/.local/state/e2e-verify-42.loop.local.json"
touch "$FAKE_CDT_ROOT/fail-stop"
assert_eq "cancel-loop fails when browser cleanup fails" "false" \
  "$(cd "$CANCEL_LOOP" && succeeds bash "$CLEANUP_SCRIPT")"
assert_eq "cancel-loop keeps the loop for retry" "true" "$([ -f "$CANCEL_STATE" ] && echo true || echo false)"
rm -f "$FAKE_CDT_ROOT/fail-stop"
assert_eq "cancel-loop retry succeeds" "true" "$(cd "$CANCEL_LOOP" && succeeds bash "$CLEANUP_SCRIPT" e2e-verify-42)"
assert_eq "cancel-loop stops the browser" "false" "$(daemon_alive "$CANCEL_PID")"

HOOK_BROWSER="$WORK/runs/hook/session.json"
/bin/bash "$HELPER" start "$HOOK_BROWSER" >/dev/null
HOOK_PID=$(state_field "$HOOK_BROWSER" daemon_pid)
HOOK_LOOP=$(loop_fixture hook "$HOOK_BROWSER")
HOOK_STATE="$HOOK_LOOP/.local/state/e2e-verify-42.loop.local.json"
HOOK_TRANSCRIPT="$HOOK_LOOP/transcript.jsonl"
(
  source "$LOOP_LIB"
  set_loop_terminal_result "$HOOK_STATE" "verified" "" "completed" "VERIFIED"
)
printf '%s\n' '{"role":"assistant","message":{"content":[{"type":"text","text":"<done>VERIFIED</done>"}]}}' > "$HOOK_TRANSCRIPT"
run_hook() {
  (
    cd "$HOOK_LOOP"
    jq -n --arg transcript "$HOOK_TRANSCRIPT" \
      '{session_id:"hook-session",transcript_path:$transcript}' | /bin/bash "$STOP_HOOK" 2>/dev/null
  )
}
touch "$FAKE_CDT_ROOT/fail-stop"
HOOK_OUTPUT=$(run_hook)
assert_eq "stop hook blocks when browser cleanup fails" "block" "$(jq -r '.decision // empty' <<< "$HOOK_OUTPUT" 2>/dev/null)"
assert_eq "stop hook keeps the loop for retry" "true" "$([ -f "$HOOK_STATE" ] && echo true || echo false)"
run_hook >/dev/null
run_hook >/dev/null
HOOK_OUTPUT=$(run_hook)
assert_eq "stop hook stops blocking after the retry cap" "" "$HOOK_OUTPUT"
assert_eq "stop hook still keeps ownership after the cap" "true" "$([ -f "$HOOK_STATE" ] && echo true || echo false)"
rm -f "$FAKE_CDT_ROOT/fail-stop"
HOOK_OUTPUT=$(run_hook)
assert_eq "stop hook allows exit once cleanup succeeds" "" "$HOOK_OUTPUT"
assert_eq "stop hook removes the loop after cleanup" "false" "$([ -f "$HOOK_STATE" ] && echo true || echo false)"
assert_eq "stop hook stops the browser" "false" "$(daemon_alive "$HOOK_PID")"

export PATH="$ORIGINAL_PATH"
echo "========================="
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "TESTS FAILED"
  exit 1
fi
echo "ALL TESTS PASSED"
