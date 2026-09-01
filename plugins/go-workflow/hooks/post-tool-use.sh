#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)

if ! PLATFORM=$(printf '%s\n' "$HOOK_INPUT" | jq -r '
  if type != "object" then "unknown"
  elif has("turn_id") and has("tool_response") then "codex"
  elif has("tool_response") or has("tool_output") then "claude"
  else "unknown"
  end
' 2>/dev/null); then
  exit 0
fi

if [ "$PLATFORM" = "unknown" ]; then
  exit 0
fi

if ! TOOL_NAME=$(printf '%s\n' "$HOOK_INPUT" | jq -r '
  .tool_name // "" |
  if type == "string" then . else tostring end
' 2>/dev/null); then
  exit 0
fi

if ! TOOL_OUTPUT=$(printf '%s\n' "$HOOK_INPUT" | jq -r --arg platform "$PLATFORM" '
  (if $platform == "codex" or has("tool_response") then .tool_response else .tool_output end) |
  if . == null then ""
  elif type == "string" then .
  else [.. | scalars | tostring] | join("\n")
  end
' 2>/dev/null); then
  exit 0
fi

detect_network_timeout() {
  printf '%s\n' "$TOOL_OUTPUT" | grep -qiE 'connection timed out|network.*(unreachable|timeout)|dial tcp.*timeout|context deadline exceeded|ETIMEDOUT|i/o timeout'
}

detect_rate_limit() {
  printf '%s\n' "$TOOL_OUTPUT" | grep -qiE 'rate limit|429|too many requests|API rate limit exceeded|secondary rate limit'
}

detect_compilation_error() {
  printf '%s\n' "$TOOL_OUTPUT" | grep -qE '^.+\.go:[0-9]+:[0-9]+: '
}

detect_lint_error() {
  printf '%s\n' "$TOOL_OUTPUT" | grep -qiE 'golangci-lint.*error|staticcheck.*error'
}

detect_permission_error() {
  printf '%s\n' "$TOOL_OUTPUT" | grep -qiE 'permission denied|403 Forbidden|EACCES|not authorized'
}

codex_command_status() {
  printf '%s\n' "$HOOK_INPUT" | jq -r '
    .tool_response |
    if type == "object" then
      if (.exit_code? // .exitCode?) != null then
        if (((.exit_code? // .exitCode?) | tonumber? // 0) != 0) then "failed" else "succeeded" end
      elif has("success") and (.success | type == "boolean") then
        if .success then "succeeded" else "failed" end
      else
        "unknown"
      end
    elif type == "string" then
      if test("(^|\\n)[[:space:]]*(Process|Command) exited with code [1-9][0-9]*[[:space:]]*(\\n|$)"; "i") then
        "failed"
      elif test("(^|\\n)[[:space:]]*(Process|Command) exited with code 0[[:space:]]*(\\n|$)"; "i") then
        "succeeded"
      else
        "unknown"
      end
    else
      "unknown"
    end
  ' 2>/dev/null
}

emit_codex_block() {
  local reason="$1"
  local guidance="$2"
  local output_excerpt="${TOOL_OUTPUT:0:4000}"
  local feedback
  feedback=$(printf '%s\n\n%s\n\nCommand output excerpt:\n%s' "$reason" "$guidance" "$output_excerpt")
  jq -cn \
    --arg reason "$feedback" \
    '{
      decision: "block",
      reason: $reason
    }'
}

emit_codex_context() {
  local context="$1"
  jq -cn \
    --arg context "$context" \
    '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $context
      }
    }'
}

emit_codex_diagnostic() {
  local failed_reason="$1"
  local unknown_reason="$2"
  local guidance="$3"
  if [ "$CODEX_COMMAND_STATUS" = failed ]; then
    emit_codex_block "$failed_reason" "$guidance"
    return
  fi
  local output_excerpt="${TOOL_OUTPUT:0:4000}"
  local context
  context=$(printf '%s\n\n%s\n\nCommand output excerpt:\n%s' \
    "$unknown_reason" \
    "Treat this as context only. Confirm that the command failed before retrying it or changing code." \
    "$output_excerpt")
  emit_codex_context "$context"
}

if [ "$PLATFORM" = "codex" ]; then
  CODEX_COMMAND_STATUS=$(codex_command_status) || CODEX_COMMAND_STATUS=unknown

  if [ "$CODEX_COMMAND_STATUS" != succeeded ] && detect_network_timeout; then
    emit_codex_diagnostic \
      "Network timeout detected after the Bash command ran." \
      "The Bash output matches a network-timeout diagnostic, but command completion status is unavailable." \
      "Do not retry automatically. Retry only after assessing whether repeating the command is safe and idempotent and whether the prior attempt may have produced side effects."
    exit 0
  fi
  if [ "$CODEX_COMMAND_STATUS" != succeeded ] && detect_rate_limit; then
    emit_codex_diagnostic \
      "Rate limit detected after the Bash command ran." \
      "The Bash output matches a rate-limit diagnostic, but command completion status is unavailable." \
      "Do not retry automatically. Retry only after assessing whether repeating the command is safe and idempotent and whether the prior attempt may have produced side effects."
    exit 0
  fi
  if [ "$CODEX_COMMAND_STATUS" != succeeded ] && detect_compilation_error; then
    emit_codex_diagnostic \
      "Go compilation error detected." \
      "The Bash output matches a Go compilation diagnostic, but command completion status is unavailable." \
      "Fix the reported compilation errors before proceeding."
    exit 0
  fi
  if [ "$CODEX_COMMAND_STATUS" != succeeded ] && detect_lint_error; then
    emit_codex_diagnostic \
      "Lint failures detected." \
      "The Bash output matches a lint-failure diagnostic, but command completion status is unavailable." \
      "Review and fix the reported lint failures before committing."
    exit 0
  fi
  if [ "$CODEX_COMMAND_STATUS" != succeeded ] && detect_permission_error; then
    emit_codex_diagnostic \
      "Permission denied by the Bash command." \
      "The Bash output matches a permission-denied diagnostic, but command completion status is unavailable." \
      "Check credentials and access rights before proceeding."
    exit 0
  fi

  output_lines=$(printf '%s\n' "$TOOL_OUTPUT" | wc -l)
  if [ "$output_lines" -gt 200 ]; then
    emit_codex_context "The Bash command produced ${output_lines} lines of output. Summarize the relevant result before proceeding."
  fi
  exit 0
fi

RETRY_STATE="${TMPDIR:-/tmp}/gopher-ai-retry-${TOOL_NAME}"

get_retry_count() {
  local retry_file="${RETRY_STATE}-$1"
  [ -f "$retry_file" ] && cat "$retry_file" || echo "0"
}

increment_retry() {
  local retry_file="${RETRY_STATE}-$1"
  printf '%s\n' "$(( $(get_retry_count "$1") + 1 ))" > "$retry_file"
}

cleanup_retry() {
  rm -f "${RETRY_STATE}-$1" 2>/dev/null
}

handle_network_timeout() {
  local retry_count
  retry_count=$(get_retry_count "network")
  if [ "$retry_count" -lt 3 ]; then
    increment_retry "network"
    local wait_seconds=$(( (retry_count + 1) * 5 ))
    echo "Network timeout (attempt $((retry_count+1))/3). Retrying in ${wait_seconds}s..." >&2
    sleep "$wait_seconds"
    printf '{"retry":true,"reason":"Network timeout - retry %d/3"}\n' "$((retry_count+1))"
    exit 0
  fi
  cleanup_retry "network"
  echo "Network timeout persists after 3 retries. Check connectivity." >&2
}

handle_rate_limit() {
  local retry_count
  retry_count=$(get_retry_count "ratelimit")
  if [ "$retry_count" -lt 3 ]; then
    increment_retry "ratelimit"
    local wait_seconds=$(( 30 * (2 ** retry_count) ))
    echo "Rate limit hit (attempt $((retry_count+1))/3). Waiting ${wait_seconds}s..." >&2
    sleep "$wait_seconds"
    printf '{"retry":true,"reason":"Rate limit - retry %d/3 after %ds"}\n' "$((retry_count+1))" "$wait_seconds"
    exit 0
  fi
  cleanup_retry "ratelimit"
  echo "Rate limit persists after 3 retries. Check API quota." >&2
}

if detect_network_timeout; then handle_network_timeout; exit 0; fi
if detect_rate_limit; then handle_rate_limit; exit 0; fi

if detect_compilation_error; then
  echo "Go compilation error detected. Fix the reported errors before proceeding." >&2
fi
if detect_lint_error; then
  echo "Lint failures detected. Review and fix before committing." >&2
fi
if detect_permission_error; then
  echo "Permission denied. Check credentials and access rights." >&2
fi

output_lines=$(printf '%s\n' "$TOOL_OUTPUT" | wc -l)
if [ "$output_lines" -gt 200 ]; then
  echo "Note: Tool output was ${output_lines} lines." >&2
fi

cleanup_retry "network"
cleanup_retry "ratelimit"
exit 0
