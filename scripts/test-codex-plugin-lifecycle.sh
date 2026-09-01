#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPECTED_CODEX_VERSION="${CODEX_LIFECYCLE_EXPECTED_VERSION:-}"
TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/gopher-ai-codex-lifecycle.XXXXXX")"
FIXTURE_WORK="$TEST_ROOT/fixture-work"
SERVER_ROOT="$TEST_ROOT/server"
SERVER_STATE="$TEST_ROOT/server-state"
TEST_HOME="$TEST_ROOT/home"
CODEX_HOME="$TEST_HOME/.codex"
PLUGIN_DATA_ROOT="$CODEX_HOME/plugins/data/go-workflow-gopher-ai"
FIRST_WORKSPACE="$TEST_ROOT/first-workspace"
SECOND_WORKSPACE="$TEST_ROOT/second-workspace"
THIRD_WORKSPACE="$TEST_ROOT/third-workspace"
LOG_DIR="$TEST_ROOT/logs"
PORT_FILE="$TEST_ROOT/server.port"
ACTIVE_PIDS=""
ACTIVE_PGIDS=""
OWNED_PID=""
PROBE_COMMAND="printf '%s\n' 'probe.go:1:1: undefined: lifecycleProbe' >&2; exit 1"
PROBE_PROMPT="Run the lifecycle-post-tool-use-probe sentinel with the shell tool."
HOOK_INPUT_CAPTURE="$LOG_DIR/post-tool-use.input.json"
HOOK_OUTPUT_CAPTURE="$LOG_DIR/post-tool-use.output.json"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

register_pid() {
    ACTIVE_PIDS="$ACTIVE_PIDS $1"
}

unregister_pid() {
    local removed_pid="$1"
    local retained_pids=""
    local pid
    for pid in $ACTIVE_PIDS; do
        if [[ "$pid" != "$removed_pid" ]]; then
            retained_pids="$retained_pids $pid"
        fi
    done
    ACTIVE_PIDS="$retained_pids"
}

register_pgid() {
    ACTIVE_PGIDS="$ACTIVE_PGIDS $1"
}

unregister_pgid() {
    local removed_pgid="$1"
    local retained_pgids=""
    local pgid
    for pgid in $ACTIVE_PGIDS; do
        if [[ "$pgid" != "$removed_pgid" ]]; then
            retained_pgids="$retained_pgids $pgid"
        fi
    done
    ACTIVE_PGIDS="$retained_pgids"
}

start_owned_process() {
    python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" &
    OWNED_PID=$!
    register_pid "$OWNED_PID"
    register_pgid "$OWNED_PID"
}

terminate_process_group() {
    local pgid="$1"
    local attempts="${2:-50}"
    local timeout_marker="$TEST_ROOT/process-group-$pgid.timeout"
    local watchdog_pid
    if ! kill -0 -- "-$pgid" 2>/dev/null; then
        return 0
    fi
    (
        local attempt
        for attempt in $(seq 1 "$attempts"); do
            if ! kill -0 -- "-$pgid" 2>/dev/null; then
                exit 0
            fi
            sleep 0.1
        done
        if kill -0 -- "-$pgid" 2>/dev/null; then
            : > "$timeout_marker"
            kill -KILL -- "-$pgid" 2>/dev/null || true
        fi
    ) &
    watchdog_pid=$!
    kill -TERM -- "-$pgid" 2>/dev/null || true
    wait "$pgid" 2>/dev/null || true
    unregister_pid "$pgid"
    while kill -0 -- "-$pgid" 2>/dev/null && [[ ! -f "$timeout_marker" ]]; do
        sleep 0.1
    done
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    [[ ! -f "$timeout_marker" ]]
}

terminate_active_process_groups() {
    local timed_out=false
    local pgid
    for pgid in $ACTIVE_PGIDS; do
        if ! terminate_process_group "$pgid"; then
            timed_out=true
        fi
    done
    ACTIVE_PGIDS=""
    [[ "$timed_out" == false ]]
}

terminate_active_processes() {
    local timed_out=false
    local pid watchdog_pid timeout_marker
    for pid in $ACTIVE_PIDS; do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            continue
        fi
        timeout_marker="$TEST_ROOT/process-$pid.timeout"
        (
            sleep 5
            if kill -0 "$pid" 2>/dev/null; then
                : > "$timeout_marker"
                kill -KILL "$pid" 2>/dev/null || true
            fi
        ) &
        watchdog_pid=$!
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
        if [[ -f "$timeout_marker" ]]; then
            timed_out=true
        fi
    done
    ACTIVE_PIDS=""
    [[ "$timed_out" == false ]]
}

remove_test_root() {
    local attempt remove_error=""
    for attempt in $(seq 1 20); do
        if remove_error=$(rm -rf -- "$TEST_ROOT" 2>&1) && [[ ! -e "$TEST_ROOT" ]]; then
            return 0
        fi
        sleep 0.1
    done
    printf 'FAIL: lifecycle temporary tree cleanup did not drain: %s\n' "$remove_error" >&2
    return 1
}

dump_diagnostics() {
    printf '\n=== Codex lifecycle smoke diagnostics ===\n' >&2
    printf 'test root: %s\n' "$TEST_ROOT" >&2
    local log_file
    for log_file in "$LOG_DIR"/*; do
        [[ -f "$log_file" ]] || continue
        printf '\n--- %s ---\n' "$(basename "$log_file")" >&2
        sed -n '1,240p' "$log_file" >&2
    done
    if [[ -d "$CODEX_HOME/plugins" ]]; then
        printf '\n--- installed plugin roots ---\n' >&2
        local plugin_root
        for plugin_root in "$CODEX_HOME/plugins/cache/gopher-ai"/*/*; do
            [[ -d "$plugin_root" ]] || continue
            printf '%s\n' "$plugin_root" >&2
        done
    fi
    local workspace
    for workspace in "$FIRST_WORKSPACE" "$SECOND_WORKSPACE" "$THIRD_WORKSPACE"; do
        if [[ -f "$workspace/.local/state/loop-debug.log" ]]; then
            printf '\n--- %s stop-hook log ---\n' "$(basename "$workspace")" >&2
            sed -n '1,120p' "$workspace/.local/state/loop-debug.log" >&2
        fi
    done
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    local cleanup_failure=""
    if ! terminate_active_process_groups; then
        cleanup_failure="owned lifecycle process groups did not drain within 5 seconds"
    fi
    if ! terminate_active_processes; then
        cleanup_failure="${cleanup_failure:+$cleanup_failure; }owned lifecycle processes did not drain within 5 seconds"
    fi
    if [[ -n "$cleanup_failure" ]]; then
        printf 'FAIL: %s\n' "$cleanup_failure" >&2
        status=1
    fi
    if [[ "$status" -ne 0 ]]; then
        dump_diagnostics
    fi
    if ! remove_test_root; then
        status=1
    fi
    exit "$status"
}

trap cleanup EXIT INT TERM

for command_name in codex curl git jq python3; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
done

CODEX_VERSION_OUTPUT="$(codex --version 2>&1)" \
    || fail "codex --version failed: ${CODEX_VERSION_OUTPUT:-no output}"
ACTUAL_CODEX_VERSION="$(awk '$1 == "codex-cli" { print $2; exit }' <<< "$CODEX_VERSION_OUTPUT")"
[[ -n "$ACTUAL_CODEX_VERSION" ]] \
    || fail "could not parse Codex CLI version from: $CODEX_VERSION_OUTPUT"
printf 'Codex CLI version: %s\n' "$ACTUAL_CODEX_VERSION"
if [[ -n "$EXPECTED_CODEX_VERSION" ]]; then
    [[ "$ACTUAL_CODEX_VERSION" == "$EXPECTED_CODEX_VERSION" ]] \
        || fail "expected codex-cli $EXPECTED_CODEX_VERSION, got $ACTUAL_CODEX_VERSION"
fi

mkdir -p \
    "$FIXTURE_WORK/.agents/plugins" \
    "$FIXTURE_WORK/plugins" \
    "$SERVER_ROOT" \
    "$SERVER_STATE" \
    "$CODEX_HOME" \
    "$FIRST_WORKSPACE" \
    "$SECOND_WORKSPACE" \
    "$THIRD_WORKSPACE" \
    "$LOG_DIR"

wait_for_marker() {
    local marker="$1"
    local attempt
    for attempt in $(seq 1 50); do
        [[ -f "$marker" ]] && return 0
        sleep 0.1
    done
    return 1
}

assert_process_group_drain() {
    local fixture_root="$TEST_ROOT/process-group-regression"
    local paused_marker="$fixture_root/paused-started"
    local resistant_marker="$fixture_root/resistant-started"
    local paused_pid resistant_pid
    mkdir -p "$fixture_root"
    start_owned_process bash -c '
        trap "exit 0" TERM
        mkdir -p "$1/.tmp/plugins-clone-paused/plugins"
        : > "$1/paused-started"
        sleep 30 &
        wait
    ' _ "$fixture_root"
    paused_pid="$OWNED_PID"
    wait_for_marker "$paused_marker" || fail "paused process-group fixture did not start"
    terminate_process_group "$paused_pid" \
        || fail "paused owned process group did not drain after TERM"
    wait "$paused_pid" 2>/dev/null || true
    unregister_pid "$paused_pid"
    unregister_pgid "$paused_pid"
    start_owned_process bash -c '
        trap "" TERM
        mkdir -p "$1/.tmp/plugins-clone-resistant/plugins"
        : > "$1/resistant-started"
        while :; do sleep 1; done
    ' _ "$fixture_root"
    resistant_pid="$OWNED_PID"
    wait_for_marker "$resistant_marker" || fail "resistant process-group fixture did not start"
    if terminate_process_group "$resistant_pid" 2; then
        fail "process-group drain accepted a TERM-resistant writer"
    fi
    wait "$resistant_pid" 2>/dev/null || true
    unregister_pid "$resistant_pid"
    unregister_pgid "$resistant_pid"
    rm -rf -- "$fixture_root"
}

assert_process_group_drain

for plugin_dir in "$ROOT_DIR"/plugins/*; do
    [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
    cp -R "$plugin_dir" "$FIXTURE_WORK/plugins/"
done
cp "$ROOT_DIR/.agents/plugins/marketplace.json" \
    "$FIXTURE_WORK/.agents/plugins/marketplace.json"

POST_TOOL_USE_CAPTURE="$FIXTURE_WORK/plugins/go-workflow/hooks/post-tool-use-capture.sh"
cat > "$POST_TOOL_USE_CAPTURE" <<'EOF'
#!/bin/bash
set -euo pipefail

HOOK_ROOT="$(cd "$(dirname "$0")" && pwd)"
INPUT_PATH="${CODEX_LIFECYCLE_HOOK_INPUT:?}"
OUTPUT_PATH="${CODEX_LIFECYCLE_HOOK_OUTPUT:?}"
cat > "$INPUT_PATH"
set +e
"$HOOK_ROOT/post-tool-use.sh" < "$INPUT_PATH" > "$OUTPUT_PATH"
status=$?
set -e
cat "$OUTPUT_PATH"
exit "$status"
EOF
chmod +x "$POST_TOOL_USE_CAPTURE"
jq '(.hooks.PostToolUse[0].hooks[0].command) = "${CLAUDE_PLUGIN_ROOT}/hooks/post-tool-use-capture.sh"' \
    "$FIXTURE_WORK/plugins/go-workflow/hooks/hooks.json" \
    > "$FIXTURE_WORK/plugins/go-workflow/hooks/hooks.json.tmp"
mv "$FIXTURE_WORK/plugins/go-workflow/hooks/hooks.json.tmp" \
    "$FIXTURE_WORK/plugins/go-workflow/hooks/hooks.json"

set_fixture_version() {
    local version="$1"
    local manifest
    for manifest in \
        "$FIXTURE_WORK/plugins/go-workflow/.claude-plugin/plugin.json" \
        "$FIXTURE_WORK/plugins/go-workflow/.codex-plugin/plugin.json"; do
        jq --arg version "$version" '.version = $version' "$manifest" > "$manifest.tmp"
        mv "$manifest.tmp" "$manifest"
    done
}

FIRST_VERSION="1.7.2-smoke.1"
SECOND_VERSION="1.7.2-smoke.2"
set_fixture_version "$FIRST_VERSION"

git -C "$FIXTURE_WORK" init -q -b main
git -C "$FIXTURE_WORK" config user.name "Codex Lifecycle Smoke"
git -C "$FIXTURE_WORK" config user.email "codex-lifecycle@example.com"
git -C "$FIXTURE_WORK" add .
git -C "$FIXTURE_WORK" commit -qm "$FIRST_VERSION"
git init -q --bare "$SERVER_ROOT/fixture.git"
git -C "$FIXTURE_WORK" remote add origin "$SERVER_ROOT/fixture.git"
git -C "$FIXTURE_WORK" push -q -u origin main
git --git-dir="$SERVER_ROOT/fixture.git" symbolic-ref HEAD refs/heads/main
git --git-dir="$SERVER_ROOT/fixture.git" update-server-info

python3 "$SCRIPT_DIR/test-codex-plugin-lifecycle-server.py" \
    --directory "$SERVER_ROOT" \
    --port-file "$PORT_FILE" \
    --state-dir "$SERVER_STATE" \
    > "$LOG_DIR/server.stdout" 2> "$LOG_DIR/server.stderr" &
SERVER_PID=$!
register_pid "$SERVER_PID"

wait_for_file() {
    local path="$1"
    local description="$2"
    local attempt
    for attempt in $(seq 1 600); do
        [[ -f "$path" ]] && return 0
        sleep 0.1
    done
    fail "timed out waiting for $description"
}

wait_for_session_request() {
    local path="$1"
    local pid="$2"
    local description="$3"
    local attempt
    for attempt in $(seq 1 600); do
        [[ -f "$path" ]] && return 0
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid" 2>/dev/null || true
            unregister_pid "$pid"
            if ! kill -0 -- "-$pid" 2>/dev/null; then
                unregister_pgid "$pid"
            fi
            fail "$description process exited before contacting the Responses server"
        fi
        sleep 0.1
    done
    fail "timed out waiting for $description"
}

wait_for_file "$PORT_FILE" "lifecycle server port"
PORT="$(cat "$PORT_FILE")"
MARKETPLACE_URL="http://127.0.0.1:$PORT/fixture.git"
RESPONSES_BASE_URL="http://127.0.0.1:$PORT/v1"

for attempt in $(seq 1 100); do
    if curl -fsS "$MARKETPLACE_URL/info/refs" >/dev/null 2>&1; then
        break
    fi
    [[ "$attempt" -lt 100 ]] || fail "local Git marketplace did not become ready"
    sleep 0.1
done

run_installer() {
    local installer_pid installer_status
    start_owned_process env \
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        GOPHER_AI_REPO="$MARKETPLACE_URL" \
        GOPHER_AI_REF=main \
        bash -c 'cd "$1" && exec bash "$2" --user' \
        _ "$TEST_ROOT" "$ROOT_DIR/scripts/install-codex.sh"
    installer_pid="$OWNED_PID"
    if wait "$installer_pid"; then
        installer_status=0
    else
        installer_status=$?
    fi
    unregister_pid "$installer_pid"
    if ! kill -0 -- "-$installer_pid" 2>/dev/null; then
        unregister_pgid "$installer_pid"
    fi
    return "$installer_status"
}

if ! run_installer > "$LOG_DIR/installer-first.stdout" 2> "$LOG_DIR/installer-first.stderr"; then
    fail "real Codex first plugin install failed"
fi

FIRST_ROOT="$CODEX_HOME/plugins/cache/gopher-ai/go-workflow/$FIRST_VERSION"
[[ -d "$FIRST_ROOT" ]] || fail "first install did not publish the expected root"
[[ "$(jq -r '.version' "$FIRST_ROOT/.codex-plugin/plugin.json")" == "$FIRST_VERSION" ]] \
    || fail "first installed root has the wrong version"
[[ -x "$FIRST_ROOT/hooks/codex-cleanup-on-start.sh" ]] \
    || fail "first SessionStart hook path is missing or not executable: $FIRST_ROOT/hooks/codex-cleanup-on-start.sh"
[[ -x "$FIRST_ROOT/hooks/stop-hook.sh" ]] \
    || fail "first Stop hook path is missing or not executable: $FIRST_ROOT/hooks/stop-hook.sh"
printf 'first=%s\n' "$FIRST_ROOT" > "$LOG_DIR/roots.log"

start_session() {
    local label="$1"
    local workspace="$2"
    local prompt="${3:-Reply with exactly lifecycle-ok and do not use tools.}"
    local hook_input="${4:-}"
    local hook_output="${5:-}"
    local sandbox_mode="${6:-read-only}"
    start_owned_process env \
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        OPENAI_API_KEY=dummy \
        CODEX_LIFECYCLE_HOOK_INPUT="$hook_input" \
        CODEX_LIFECYCLE_HOOK_OUTPUT="$hook_output" \
        codex exec \
        --cd "$workspace" \
        --skip-git-repo-check \
        --dangerously-bypass-hook-trust \
        --sandbox "$sandbox_mode" \
        --json \
        -c 'model_provider="lifecycle"' \
        -c "model_providers.lifecycle={ name = \"Lifecycle\", base_url = \"$RESPONSES_BASE_URL\", env_key = \"OPENAI_API_KEY\", wire_api = \"responses\", supports_websockets = false }" \
        "$prompt" \
        </dev/null \
        > "$LOG_DIR/$label.stdout" 2> "$LOG_DIR/$label.stderr"
    SESSION_PID="$OWNED_PID"
}

finish_session() {
    local pid="$1"
    local label="$2"
    local timeout_marker="$SERVER_STATE/$label.timeout"
    (
        sleep 60
        if kill -0 "$pid" 2>/dev/null; then
            : > "$timeout_marker"
            kill -TERM -- "-$pid" 2>/dev/null || true
        fi
    ) &
    local watchdog_pid=$!
    register_pid "$watchdog_pid"
    local status
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi
    unregister_pid "$pid"
    if ! kill -0 -- "-$pid" 2>/dev/null; then
        unregister_pgid "$pid"
    fi
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    unregister_pid "$watchdog_pid"
    [[ ! -f "$timeout_marker" ]] || fail "$label session timed out"
    [[ "$status" -eq 0 ]] || fail "$label session exited with code $status"
}

assert_session() {
    local label="$1"
    local workspace="$2"
    local version="$3"
    local expected_reply="${4:-lifecycle-ok}"
    local combined="$LOG_DIR/$label.combined"
    sed -n '1,240p' "$LOG_DIR/$label.stdout" > "$combined"
    sed -n '1,240p' "$LOG_DIR/$label.stderr" >> "$combined"
    grep -Fq "$expected_reply" "$combined" || fail "$label session did not complete the expected turn"
    if grep -Eiq '(SessionStart|Stop) hook \(failed\)|hook exited with code [1-9][0-9]*|hook.*(not found|No such file)|exit(ed)? (with )?(code )?127' "$combined"; then
        fail "$label session reported a hook failure"
    fi
    [[ -f "$PLUGIN_DATA_ROOT/.gopher-ai-cleanup-v3-$version" ]] \
        || fail "$label SessionStart hook did not create its version marker"
    grep -q 'stop-hook: entered' "$workspace/.local/state/loop-debug.log" \
        || fail "$label Stop hook did not record entry"
}

start_session first "$FIRST_WORKSPACE"
FIRST_SESSION_PID=$SESSION_PID
wait_for_session_request "$SERVER_STATE/1.requested" "$FIRST_SESSION_PID" "first Responses request"
[[ -f "$PLUGIN_DATA_ROOT/.gopher-ai-cleanup-v3-$FIRST_VERSION" ]] \
    || fail "first SessionStart hook did not run before the minimal turn"

set_fixture_version "$SECOND_VERSION"
git -C "$FIXTURE_WORK" add \
    plugins/go-workflow/.claude-plugin/plugin.json \
    plugins/go-workflow/.codex-plugin/plugin.json
git -C "$FIXTURE_WORK" commit -qm "$SECOND_VERSION"
git -C "$FIXTURE_WORK" push -q origin main
git --git-dir="$SERVER_ROOT/fixture.git" update-server-info

set +e
run_installer > "$LOG_DIR/installer-active.stdout" 2> "$LOG_DIR/installer-active.stderr"
ACTIVE_INSTALL_STATUS=$?
set -e
[[ "$ACTIVE_INSTALL_STATUS" -ne 0 ]] \
    || fail "updated plugin install proceeded while a Codex session was active"
grep -q 'Codex processes are running' "$LOG_DIR/installer-active.stderr" \
    || fail "active-session refusal did not explain how to recover"
[[ -x "$FIRST_ROOT/hooks/codex-cleanup-on-start.sh" ]] \
    || fail "active SessionStart hook path disappeared during refused update"
[[ -x "$FIRST_ROOT/hooks/stop-hook.sh" ]] \
    || fail "active Stop hook path disappeared during refused update"

: > "$SERVER_STATE/1.release"
finish_session "$FIRST_SESSION_PID" first
assert_session first "$FIRST_WORKSPACE" "$FIRST_VERSION"

if ! run_installer > "$LOG_DIR/installer-second.stdout" 2> "$LOG_DIR/installer-second.stderr"; then
    fail "real Codex updated plugin install failed after the active session exited"
fi

SECOND_ROOT="$CODEX_HOME/plugins/cache/gopher-ai/go-workflow/$SECOND_VERSION"
printf 'second=%s\n' "$SECOND_ROOT" >> "$LOG_DIR/roots.log"
[[ -d "$SECOND_ROOT" ]] || fail "updated install did not publish the expected root"
[[ "$SECOND_ROOT" != "$FIRST_ROOT" ]] || fail "plugin update did not activate a distinct versioned root"
[[ "$(jq -r '.version' "$SECOND_ROOT/.codex-plugin/plugin.json")" == "$SECOND_VERSION" ]] \
    || fail "updated installed root has the wrong version"
[[ -x "$FIRST_ROOT/hooks/codex-cleanup-on-start.sh" ]] \
    || fail "active SessionStart hook path disappeared during update: $FIRST_ROOT/hooks/codex-cleanup-on-start.sh"
[[ -x "$FIRST_ROOT/hooks/stop-hook.sh" ]] \
    || fail "active Stop hook path disappeared during update: $FIRST_ROOT/hooks/stop-hook.sh"

start_session second "$SECOND_WORKSPACE"
SECOND_SESSION_PID=$SESSION_PID
wait_for_session_request "$SERVER_STATE/2.requested" "$SECOND_SESSION_PID" "post-update Responses request"
[[ -f "$PLUGIN_DATA_ROOT/.gopher-ai-cleanup-v3-$SECOND_VERSION" ]] \
    || fail "post-update SessionStart hook did not run before the minimal turn"
: > "$SERVER_STATE/2.release"
finish_session "$SECOND_SESSION_PID" second
assert_session second "$SECOND_WORKSPACE" "$SECOND_VERSION"

start_session probe "$THIRD_WORKSPACE" "$PROBE_PROMPT" "$HOOK_INPUT_CAPTURE" "$HOOK_OUTPUT_CAPTURE" danger-full-access
PROBE_SESSION_PID=$SESSION_PID
wait_for_session_request "$SERVER_STATE/3.requested" "$PROBE_SESSION_PID" "probe Responses request"
: > "$SERVER_STATE/3.release"
wait_for_session_request "$HOOK_INPUT_CAPTURE" "$PROBE_SESSION_PID" "PostToolUse input capture"
wait_for_session_request "$HOOK_OUTPUT_CAPTURE" "$PROBE_SESSION_PID" "PostToolUse output capture"
wait_for_session_request "$SERVER_STATE/4.requested" "$PROBE_SESSION_PID" "probe function output request"

jq -e --arg command "$PROBE_COMMAND" '
    .hook_event_name == "PostToolUse" and
    (.turn_id | type == "string" and length > 0) and
    .tool_name == "Bash" and
    (.tool_use_id | type == "string" and length > 0) and
    .tool_input.command == $command and
    (.tool_response | type == "string" and contains("lifecycleProbe")) and
    (has("tool_output") | not)
' "$HOOK_INPUT_CAPTURE" >/dev/null \
    || fail "PostToolUse input did not match the Codex hook payload"

jq -e '
    type == "object" and
    (has("decision") | not) and
    (has("retry") | not) and
    ((keys - ["continue", "decision", "hookSpecificOutput", "reason", "stopReason", "systemMessage"]) | length == 0) and
    (((.hookSpecificOutput // {}) | keys - ["additionalContext", "hookEventName"]) | length == 0) and
    .hookSpecificOutput.hookEventName == "PostToolUse" and
    (.hookSpecificOutput.additionalContext | test("compilation"; "i")) and
    (.hookSpecificOutput.additionalContext | test("status.*unavailable"; "i")) and
    (.hookSpecificOutput.additionalContext | contains("probe.go:1:1: undefined: lifecycleProbe"))
' "$HOOK_OUTPUT_CAPTURE" >/dev/null \
    || fail "PostToolUse output was not supported Codex diagnostic context"

jq -e '
    ([.. | objects | select(
        (.type? == "function_call_output" or .type? == "custom_tool_call_output") and
        .call_id? == "post-tool-use-probe" and
        ((.output? // "") | tostring | contains("probe.go:1:1: undefined: lifecycleProbe"))
    )] | length == 1) and
    ([.. | strings] | join("\n") |
        test("compilation"; "i") and
        test("status.*unavailable"; "i") and
        contains("probe.go:1:1: undefined: lifecycleProbe"))
' "$SERVER_STATE/4.request.json" >/dev/null \
    || fail "follow-up request did not contain the tool result and hook steering"

: > "$SERVER_STATE/4.release"
finish_session "$PROBE_SESSION_PID" probe
assert_session probe "$THIRD_WORKSPACE" "$SECOND_VERSION" "lifecycle-hook-ok"

printf 'Codex %s plugin lifecycle smoke test passed.\n' "$ACTUAL_CODEX_VERSION"
