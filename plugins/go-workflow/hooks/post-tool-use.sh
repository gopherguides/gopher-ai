#!/bin/bash
# PostToolUse error detection and auto-retry hook for go-workflow
set -euo pipefail
HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_output // empty' 2>/dev/null)
RETRY_STATE="${TMPDIR:-/tmp}/.claude-hook-retry-$$"

detect_network_timeout() {
  echo "$TOOL_OUTPUT" | grep -qiE 'connection timed out|network.*(unreachable|timeout)|dial tcp.*timeout|context deadline exceeded|ETIMEDOUT'
}
detect_rate_limit() {
  echo "$TOOL_OUTPUT" | grep -qiE 'rate limit|429|too many requests|API rate limit exceeded|secondary rate limit'
}
get_retry_count() { local f="${RETRY_STATE}-$1"; [ -f "$f" ] && cat "$f" || echo "0"; }
increment_retry() { local f="${RETRY_STATE}-$1"; echo $(( $(get_retry_count "$1") + 1 )) > "$f"; }
cleanup_retry() { rm -f "${RETRY_STATE}-$1" 2>/dev/null; }

handle_network_timeout() {
  local rc; rc=$(get_retry_count "network")
  if [ "$rc" -lt 3 ]; then
    increment_retry "network"
    local wait=$(( (rc + 1) * 5 ))
    echo "Network timeout (attempt $((rc+1))/3). Retrying in ${wait}s..." >&2
    sleep "$wait"
    printf '{"retry":true,"reason":"Network timeout - retry %d/3"}\n' "$((rc+1))"
    exit 0
  fi
  cleanup_retry "network"
  echo "Network timeout persists after 3 retries. Check connectivity." >&2
}

handle_rate_limit() {
  local rc; rc=$(get_retry_count "ratelimit")
  if [ "$rc" -lt 3 ]; then
    increment_retry "ratelimit"
    local wait=$(( 30 * (2 ** rc) ))
    echo "Rate limit hit (attempt $((rc+1))/3). Waiting ${wait}s..." >&2
    sleep "$wait"
    printf '{"retry":true,"reason":"Rate limit - retry %d/3 after %ds"}\n' "$((rc+1))" "$wait"
    exit 0
  fi
  cleanup_retry "ratelimit"
  echo "Rate limit persists after 3 retries. Check API quota." >&2
}

# Transient failures (may retry)
if detect_network_timeout; then handle_network_timeout; exit 0; fi
if detect_rate_limit; then handle_rate_limit; exit 0; fi

# Non-transient errors (inform only)
if echo "$TOOL_OUTPUT" | grep -qE '^.+\.go:[0-9]+:[0-9]+: '; then
  echo "Go compilation error detected. Fix the reported errors before proceeding." >&2
fi
if echo "$TOOL_OUTPUT" | grep -qiE 'golangci-lint.*error|staticcheck.*error'; then
  echo "Lint failures detected. Review and fix before committing." >&2
fi
if echo "$TOOL_OUTPUT" | grep -qiE 'permission denied|403 Forbidden|EACCES|not authorized'; then
  echo "Permission denied. Check credentials and access rights." >&2
fi

# Output optimization
output_lines=$(echo "$TOOL_OUTPUT" | wc -l)
if [ "$output_lines" -gt 200 ]; then
  echo "Note: Tool output was ${output_lines} lines." >&2
fi

cleanup_retry "network"
cleanup_retry "ratelimit"
exit 0
