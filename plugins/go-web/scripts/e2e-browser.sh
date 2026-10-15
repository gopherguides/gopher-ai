#!/bin/bash
# Own one isolated Chrome DevTools CLI session for a single E2E run.
# Usage: e2e-browser.sh start|call|stop STATE_FILE [TOOL ARGS...]
#
# start  records ownership in STATE_FILE before launching a uniquely named,
#        isolated browser session, then opens a private marker page.
# call   runs one Chrome DevTools tool in the owned session after proving the
#        recorded daemon and marker page still exist; it never reconnects.
# stop   stops exactly the recorded session, verifies shutdown, and marks the
#        state inactive. A failed stop leaves the state active for retry.

set -euo pipefail
umask 077

if [ "$#" -lt 2 ]; then
  echo "Usage: e2e-browser.sh start|call|stop STATE_FILE [TOOL ARGS...]" >&2
  exit 2
fi

ACTION="$1"
STATE_FILE="$2"
shift 2
export NODE_NO_WARNINGS=1

die() {
  echo "e2e-browser: $*" >&2
  exit 1
}

update_state() {
  local tmp_file
  tmp_file=$(mktemp "${STATE_FILE}.XXXXXX") || return 1
  if jq "$@" "$STATE_FILE" > "$tmp_file"; then
    mv "$tmp_file" "$STATE_FILE"
  else
    rm -f "$tmp_file"
    return 1
  fi
}

load_state() {
  [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] || die "missing browser state file: $STATE_FILE"
  jq -e '.schema == 1 and
    (.cli | type == "string" and startswith("/")) and
    (.session | type == "string" and test("^[a-f0-9]{32}$")) and
    (.active | type == "boolean")' "$STATE_FILE" >/dev/null 2>&1 ||
    die "invalid browser state file: $STATE_FILE"
  CLI_PATH=$(jq -r '.cli' "$STATE_FILE")
  SESSION_ID=$(jq -r '.session' "$STATE_FILE")
  ACTIVE=$(jq -r '.active' "$STATE_FILE")
  DAEMON_PID=$(jq -r '.daemon_pid // empty' "$STATE_FILE")
  MARKER_ID=$(jq -r '.marker_id // empty' "$STATE_FILE")
  MARKER_URL=$(jq -r '.marker_url // empty' "$STATE_FILE")
}

process_alive() {
  local state
  state=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
  case "$state" in
    ""|*Z*) return 1 ;;
  esac
}

run_bounded() {
  local limit="$1" pid waited=0
  shift
  "$@" &
  pid=$!
  while process_alive "$pid"; do
    if [ "$waited" -ge "$((limit * 4))" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.25
    waited=$((waited + 1))
  done
  wait "$pid"
}

session_status() {
  run_bounded "${E2E_BROWSER_STATUS_TIMEOUT:-15}" "$CLI_PATH" status --sessionId="$SESSION_ID" 2>/dev/null
}

running_daemon_pid() {
  local status
  status=$(session_status) || return 1
  case "$status" in
    *"socket="*"$SESSION_ID"*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$status" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n 1
}

session_stopped() {
  local status
  status=$(session_status) || return 1
  case "$status" in
    *"daemon is not running"*) ;;
    *) return 1 ;;
  esac
  if [ -n "$DAEMON_PID" ] && process_alive "$DAEMON_PID"; then
    return 1
  fi
  return 0
}

run_tool() {
  local response
  response=$("$CLI_PATH" "$@" --sessionId="$SESSION_ID" --output-format=json) || return 1
  if ! jq -e 'type == "object" or (type == "array" and all(.[]; type == "string"))' \
      <<< "$response" >/dev/null 2>&1; then
    printf '%s\n' "$response" >&2
    return 1
  fi
  printf '%s\n' "$response"
}

owned_browser_present() {
  local pid pages
  pid=$(running_daemon_pid) || return 1
  [ -n "$pid" ] && [ "$pid" = "$DAEMON_PID" ] || return 1
  pages=$(run_tool list_pages) || return 1
  jq -e --argjson id "$MARKER_ID" --arg url "$MARKER_URL" \
    'any(.pages[]?; .id == $id and .url == $url)' <<< "$pages" >/dev/null 2>&1
}

stop_session() {
  local attempt
  if [ "$ACTIVE" != "true" ]; then
    echo "E2E browser session $SESSION_ID is already stopped."
    return 0
  fi
  [ -x "$CLI_PATH" ] || { echo "e2e-browser: recorded CLI is unavailable: $CLI_PATH" >&2; return 1; }
  if ! run_bounded "${E2E_BROWSER_STOP_TIMEOUT:-30}" "$CLI_PATH" stop --sessionId="$SESSION_ID" >/dev/null 2>&1; then
    echo "e2e-browser: stop failed or timed out for session $SESSION_ID" >&2
    return 1
  fi
  attempt=0
  until session_stopped; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "${E2E_BROWSER_STOP_POLLS:-20}" ]; then
      echo "e2e-browser: session $SESSION_ID is still running after stop" >&2
      return 1
    fi
    sleep "${E2E_BROWSER_STOP_INTERVAL:-0.25}"
  done
  update_state '.active = false' || return 1
  ACTIVE=false
  echo "E2E browser session $SESSION_ID stopped."
}

fail_start() {
  if ! stop_session >&2; then
    die "$1; cleanup failed, retry: e2e-browser.sh stop $STATE_FILE"
  fi
  die "$1"
}

case "$ACTION" in
  start)
    [ "$#" -eq 0 ] || die "start takes no tool arguments"
    if [ -e "$STATE_FILE" ] || [ -L "$STATE_FILE" ]; then
      die "state file already exists; reuse its session or stop it first: $STATE_FILE"
    fi
    CLI_PATH=$(command -v chrome-devtools) || die "chrome-devtools CLI is not installed; see the e2e-verify skill for setup"
    case "$CLI_PATH" in /*) ;; *) die "chrome-devtools must resolve to an absolute path" ;; esac
    SESSION_ID=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
    mkdir -p "$(dirname "$STATE_FILE")"
    STATE_JSON=$(jq -n --arg cli "$CLI_PATH" --arg session "$SESSION_ID" \
      '{schema: 1, cli: $cli, session: $session, active: true}')
    (set -o noclobber; printf '%s\n' "$STATE_JSON" > "$STATE_FILE") 2>/dev/null ||
      die "state file already exists; reuse its session or stop it first: $STATE_FILE"
    load_state
    if ! "$CLI_PATH" start --sessionId="$SESSION_ID" --isolated \
        --headless="${E2E_BROWSER_HEADLESS:-false}" \
        --no-usage-statistics --no-performance-crux >/dev/null 2>&1; then
      fail_start "browser startup failed"
    fi
    DAEMON_PID=$(running_daemon_pid) || fail_start "browser daemon did not report a running session"
    [ -n "$DAEMON_PID" ] || fail_start "browser daemon did not report its pid"
    update_state --arg pid "$DAEMON_PID" '.daemon_pid = $pid' || fail_start "could not record daemon pid"
    MARKER_URL="data:text/html,<title>e2e-owner-$SESSION_ID</title>"
    PAGES=$(run_tool new_page "$MARKER_URL") || fail_start "could not open the ownership marker page"
    MARKER_ID=$(jq -er --arg url "$MARKER_URL" 'first(.pages[]? | select(.url == $url) | .id)' <<< "$PAGES" 2>/dev/null) ||
      fail_start "CLI did not report the ownership marker page"
    update_state --argjson id "$MARKER_ID" --arg url "$MARKER_URL" '.marker_id = $id | .marker_url = $url' ||
      fail_start "could not record the ownership marker page"
    echo "E2E browser session $SESSION_ID started."
    ;;
  call)
    [ "$#" -gt 0 ] || die "a Chrome DevTools tool name is required"
    case "$1" in
      start|stop|status) die "use the helper's start and stop actions for lifecycle changes" ;;
    esac
    for arg in "$@"; do
      case "$arg" in
        --sessionId|--sessionId=*|--output-format|--output-format=*)
          die "the helper owns --sessionId and --output-format" ;;
      esac
    done
    load_state
    [ "$ACTIVE" = "true" ] || die "session $SESSION_ID was stopped; do not restart it to collect evidence"
    [ -x "$CLI_PATH" ] || die "recorded CLI is unavailable: $CLI_PATH"
    [ -n "$DAEMON_PID" ] && [ -n "$MARKER_ID" ] || die "session $SESSION_ID never finished starting"
    owned_browser_present || die "owned browser session $SESSION_ID is unavailable; refusing to reconnect"
    RESULT=$(run_tool "$@") || die "browser tool failed: $1"
    owned_browser_present || die "owned browser session $SESSION_ID changed during $1; evidence discarded"
    printf '%s\n' "$RESULT"
    ;;
  stop)
    [ "$#" -eq 0 ] || die "stop takes no tool arguments"
    if [ ! -e "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ]; then
      echo "No E2E browser session recorded at $STATE_FILE."
      exit 0
    fi
    load_state
    stop_session || exit 1
    ;;
  *)
    die "unknown action: $ACTION"
    ;;
esac
