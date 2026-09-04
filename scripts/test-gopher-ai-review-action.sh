#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTION_DIR="$ROOT_DIR/.github/actions/gopher-ai-review"
ACTION_FILE="$ACTION_DIR/action.yml"
REVIEW_SCRIPT="$ACTION_DIR/review-api.sh"
WORKFLOW_FILE="$ROOT_DIR/.github/workflows/gopher-ai-review.yml"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-review-action-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local message="$3"

  awk -v expected="$expected" 'index($0, expected) { found = 1 } END { exit found ? 0 : 1 }' "$file" || fail "$message"
}

test_action_contract() {
  [ -f "$ACTION_FILE" ] || fail "reusable action is missing"
  [ -x "$REVIEW_SCRIPT" ] || fail "API review helper is missing or not executable"
  [ -f "$WORKFLOW_FILE" ] || fail "consumer workflow is missing"

  assert_contains "$ACTION_FILE" "\${{ github.action_path }}/review-api.sh" "action does not execute its packaged helper"
  assert_contains "$ACTION_FILE" "\${{ github.event.pull_request.head.sha || github.sha }}" "action does not publish the reviewed head SHA"

  while IFS='|' read -r action message; do
    assert_contains "$WORKFLOW_FILE" "$action" "$message"
  done <<'EOF'
opened|workflow does not review newly opened pull requests
synchronize|workflow does not re-review newly pushed heads
reopened|workflow does not review reopened pull requests
ready_for_review|workflow does not review pull requests leaving draft state
EOF
}

write_fake_curl() {
  local bin_dir="$1"

  mkdir -p "$bin_dir"
  cat > "$bin_dir/curl" <<'EOF'
set -euo pipefail

output_file=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output)
      output_file="$2"
      shift 2
      ;;
    --write-out|-X|-H|--data-binary)
      shift 2
      ;;
    -s|-S|-sS|--silent|--show-error)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

[ -n "$output_file" ]
count=0
if [ -f "$FAKE_CURL_STATE" ]; then
  count=$(cat "$FAKE_CURL_STATE")
fi
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_CURL_STATE"
printf '%s\n' "$url" >> "$FAKE_CURL_URLS"

case "$FAKE_CURL_SCENARIO:$count" in
  schema_then_success:1)
    printf '%s\n' '{"content":"training response","sources":[]}' > "$output_file"
    ;;
  schema_then_success:2)
    printf '%s\n' '{"summary":"No issues found","file_count":1,"issues":[]}' > "$output_file"
    ;;
  invalid_json_then_success:1)
    printf '%s\n' '{"api_key":"do-not-log","summary":' > "$output_file"
    ;;
  invalid_json_then_success:2)
    printf '%s\n' '{"summary":"No issues found","file_count":1,"issues":[]}' > "$output_file"
    ;;
  schema_exhausted:*)
    printf '%s\n' '{"content":"still the wrong contract","sources":[]}' > "$output_file"
    ;;
  *)
    exit 97
    ;;
esac

printf '200'
EOF
  chmod +x "$bin_dir/curl"
}

run_response_case() {
  local name="$1"
  local scenario="$2"
  local want_status="$3"
  local want_api_failed="$4"
  local want_skip_reason="$5"
  local case_root="$TEST_ROOT/$name"
  local bin_dir="$case_root/bin"
  local command_status=0

  mkdir -p "$case_root/workspace/status"
  printf '%s\n' 'diff --git a/sample.go b/sample.go' > "$case_root/workspace/pr.diff"
  : > "$case_root/output"
  : > "$case_root/urls"
  write_fake_curl "$bin_dir"

  PATH="$bin_dir:$PATH" \
  FAKE_CURL_SCENARIO="$scenario" \
  FAKE_CURL_STATE="$case_root/count" \
  FAKE_CURL_URLS="$case_root/urls" \
  GITHUB_OUTPUT="$case_root/output" \
  GITHUB_WORKSPACE="$case_root/workspace" \
  REVIEW_STATUS_DIR="$case_root/workspace/status" \
  GOPHER_AI_API_KEY="example-key" \
  GOPHER_AI_API_URL="https://example.test/api/gopher-ai/review?format=json" \
  GOPHER_AI_FOCUS="" \
  GOPHER_AI_DIFF_PATH="$case_root/workspace/pr.diff" \
  GOPHER_AI_RETRY_DELAY_SECONDS=0 \
  /bin/bash "$REVIEW_SCRIPT" > "$case_root/log" 2>&1 || command_status=$?

  [ "$command_status" -eq "$want_status" ] || fail "$name exit status = $command_status, want $want_status"
  [ "$(cat "$case_root/count")" = "2" ] || fail "$name did not make exactly two bounded attempts"
  assert_contains "$case_root/urls" '?format=github' "$name did not request the GitHub response contract"
  assert_contains "$case_root/output" "api_failed=$want_api_failed" "$name emitted the wrong API failure disposition"
  assert_contains "$case_root/output" "skip_reason=$want_skip_reason" "$name emitted the wrong skip reason"
  assert_contains "$case_root/log" 'attempt 1 of 2' "$name did not identify the failed attempt"
  assert_contains "$case_root/log" 'Response excerpt:' "$name did not log the actual response excerpt"
  if awk 'index($0, "do-not-log") { found = 1 } END { exit found ? 0 : 1 }' "$case_root/log"; then
    fail "$name exposed a secret from the malformed response"
  fi

  if [ "$want_status" -eq 0 ]; then
    assert_contains "$case_root/log" 'Retrying once.' "$name did not announce the bounded retry"
    assert_contains "$case_root/output" 'summary=No issues found' "$name did not accept the recovered response"
  else
    assert_contains "$case_root/workspace/status/status.md" 'No additional retry will occur.' "$name did not make retry exhaustion concrete"
    assert_contains "$case_root/workspace/status/status.md" 'invalid-response-schema' "$name did not report the concrete terminal cause"
  fi
}

test_action_contract

while IFS='|' read -r name scenario want_status want_api_failed want_skip_reason; do
  run_response_case "$name" "$scenario" "$want_status" "$want_api_failed" "$want_skip_reason"
done <<'EOF'
schema-drift-recovers|schema_then_success|0|false|
malformed-response-recovers|invalid_json_then_success|0|false|
schema-retry-exhausted|schema_exhausted|1|true|invalid-response-schema-retry-exhausted
EOF

echo "Gopher AI review action tests passed"
