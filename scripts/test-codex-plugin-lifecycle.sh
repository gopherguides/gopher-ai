#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPECTED_CODEX_VERSION="${CODEX_LIFECYCLE_EXPECTED_VERSION:-0.144.6}"
TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
TEST_ROOT="$(mktemp -d "$TMP_BASE/gopher-ai-codex-lifecycle.XXXXXX")"
FIXTURE_WORK="$TEST_ROOT/fixture-work"
SERVER_ROOT="$TEST_ROOT/server"
SERVER_STATE="$TEST_ROOT/server-state"
TEST_HOME="$TEST_ROOT/home"
CODEX_HOME="$TEST_HOME/.codex"
FIRST_WORKSPACE="$TEST_ROOT/first-workspace"
SECOND_WORKSPACE="$TEST_ROOT/second-workspace"
LOG_DIR="$TEST_ROOT/logs"
PORT_FILE="$TEST_ROOT/server.port"
ACTIVE_PIDS=""

fail() {
    printf 'FAIL: %s\n' "$*" >&2
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
    for workspace in "$FIRST_WORKSPACE" "$SECOND_WORKSPACE"; do
        if [[ -f "$workspace/.local/state/loop-debug.log" ]]; then
            printf '\n--- %s stop-hook log ---\n' "$(basename "$workspace")" >&2
            sed -n '1,120p' "$workspace/.local/state/loop-debug.log" >&2
        fi
    done
}

cleanup() {
    local status=$?
    trap - EXIT INT TERM
    local pid
    for pid in $ACTIVE_PIDS; do
        kill "$pid" 2>/dev/null || true
    done
    if [[ "$status" -ne 0 ]]; then
        dump_diagnostics
    fi
    rm -rf -- "$TEST_ROOT"
    exit "$status"
}

trap cleanup EXIT INT TERM

for command_name in codex curl git jq python3; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
done

ACTUAL_CODEX_VERSION="$(codex --version 2>/dev/null | awk '{print $2}')"
[[ "$ACTUAL_CODEX_VERSION" == "$EXPECTED_CODEX_VERSION" ]] \
    || fail "expected codex-cli $EXPECTED_CODEX_VERSION, got ${ACTUAL_CODEX_VERSION:-unknown}"

mkdir -p \
    "$FIXTURE_WORK/.agents/plugins" \
    "$FIXTURE_WORK/plugins" \
    "$SERVER_ROOT" \
    "$SERVER_STATE" \
    "$CODEX_HOME" \
    "$FIRST_WORKSPACE" \
    "$SECOND_WORKSPACE" \
    "$LOG_DIR"

for plugin_dir in "$ROOT_DIR"/plugins/*; do
    [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
    cp -R "$plugin_dir" "$FIXTURE_WORK/plugins/"
done
cp "$ROOT_DIR/.agents/plugins/marketplace.json" \
    "$FIXTURE_WORK/.agents/plugins/marketplace.json"

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
ACTIVE_PIDS="$ACTIVE_PIDS $SERVER_PID"

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

run_codex() {
    env \
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        OPENAI_API_KEY=dummy \
        codex "$@"
}

run_installer() {
    env \
        HOME="$TEST_HOME" \
        CODEX_HOME="$CODEX_HOME" \
        GOPHER_AI_REPO="$MARKETPLACE_URL" \
        GOPHER_AI_REF=main \
        bash "$ROOT_DIR/scripts/install-codex.sh" --user
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
    run_codex exec \
        --cd "$workspace" \
        --skip-git-repo-check \
        --dangerously-bypass-hook-trust \
        --sandbox read-only \
        --json \
        -c 'model_provider="lifecycle"' \
        -c "model_providers.lifecycle={ name = \"Lifecycle\", base_url = \"$RESPONSES_BASE_URL\", env_key = \"OPENAI_API_KEY\", wire_api = \"responses\", supports_websockets = false }" \
        "Reply with exactly lifecycle-ok and do not use tools." \
        </dev/null \
        > "$LOG_DIR/$label.stdout" 2> "$LOG_DIR/$label.stderr" &
    SESSION_PID=$!
    ACTIVE_PIDS="$ACTIVE_PIDS $SESSION_PID"
}

finish_session() {
    local pid="$1"
    local label="$2"
    local timeout_marker="$SERVER_STATE/$label.timeout"
    (
        sleep 60
        if kill -0 "$pid" 2>/dev/null; then
            : > "$timeout_marker"
            kill "$pid" 2>/dev/null || true
        fi
    ) &
    local watchdog_pid=$!
    ACTIVE_PIDS="$ACTIVE_PIDS $watchdog_pid"
    local status
    set +e
    wait "$pid"
    status=$?
    set -e
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    [[ ! -f "$timeout_marker" ]] || fail "$label session timed out"
    [[ "$status" -eq 0 ]] || fail "$label session exited with code $status"
}

assert_session() {
    local label="$1"
    local workspace="$2"
    local version="$3"
    local combined="$LOG_DIR/$label.combined"
    sed -n '1,240p' "$LOG_DIR/$label.stdout" > "$combined"
    sed -n '1,240p' "$LOG_DIR/$label.stderr" >> "$combined"
    grep -q 'lifecycle-ok' "$combined" || fail "$label session did not complete the minimal turn"
    if grep -Eiq '(SessionStart|Stop) hook \(failed\)|hook exited with code [1-9][0-9]*|hook.*(not found|No such file)|exit(ed)? (with )?(code )?127' "$combined"; then
        fail "$label session reported a hook failure"
    fi
    [[ -f "$CODEX_HOME/.gopher-ai-cleanup-v3-$version" ]] \
        || fail "$label SessionStart hook did not create its version marker"
    grep -q 'stop-hook: entered' "$workspace/.local/state/loop-debug.log" \
        || fail "$label Stop hook did not record entry"
}

start_session first "$FIRST_WORKSPACE"
FIRST_SESSION_PID=$SESSION_PID
wait_for_session_request "$SERVER_STATE/1.requested" "$FIRST_SESSION_PID" "first Responses request"
[[ -f "$CODEX_HOME/.gopher-ai-cleanup-v3-$FIRST_VERSION" ]] \
    || fail "first SessionStart hook did not run before the minimal turn"

set_fixture_version "$SECOND_VERSION"
git -C "$FIXTURE_WORK" add \
    plugins/go-workflow/.claude-plugin/plugin.json \
    plugins/go-workflow/.codex-plugin/plugin.json
git -C "$FIXTURE_WORK" commit -qm "$SECOND_VERSION"
git -C "$FIXTURE_WORK" push -q origin main
git --git-dir="$SERVER_ROOT/fixture.git" update-server-info

if ! run_installer > "$LOG_DIR/installer-second.stdout" 2> "$LOG_DIR/installer-second.stderr"; then
    fail "real Codex updated plugin install failed"
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

: > "$SERVER_STATE/1.release"
finish_session "$FIRST_SESSION_PID" first
assert_session first "$FIRST_WORKSPACE" "$FIRST_VERSION"

start_session second "$SECOND_WORKSPACE"
SECOND_SESSION_PID=$SESSION_PID
wait_for_session_request "$SERVER_STATE/2.requested" "$SECOND_SESSION_PID" "post-update Responses request"
[[ -f "$CODEX_HOME/.gopher-ai-cleanup-v3-$SECOND_VERSION" ]] \
    || fail "post-update SessionStart hook did not run before the minimal turn"
: > "$SERVER_STATE/2.release"
finish_session "$SECOND_SESSION_PID" second
assert_session second "$SECOND_WORKSPACE" "$SECOND_VERSION"

printf 'Codex %s plugin lifecycle smoke test passed.\n' "$ACTUAL_CODEX_VERSION"
