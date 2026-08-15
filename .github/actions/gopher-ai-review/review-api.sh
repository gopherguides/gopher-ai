#!/usr/bin/env bash

set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
: "${GOPHER_AI_API_URL:?GOPHER_AI_API_URL is required}"
: "${GOPHER_AI_DIFF_PATH:?GOPHER_AI_DIFF_PATH is required}"

STATUS_DIR="${REVIEW_STATUS_DIR:-$GITHUB_WORKSPACE/.gopher-ai-review}"
RESPONSE_FILE="$GITHUB_WORKSPACE/review_response.json"
PAYLOAD_FILE="$GITHUB_WORKSPACE/payload.json"
RETRY_DELAY_SECONDS="${GOPHER_AI_RETRY_DELAY_SECONDS:-2}"
MAX_ATTEMPTS=2

mkdir -p "$STATUS_DIR"

write_output() {
  local key="$1"
  local value="${2//$'\r'/}"

  value="${value//$'\n'/ }"
  printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
}

redacted_response_excerpt() {
  local response_file="$1"
  local excerpt

  if jq -e . "$response_file" >/dev/null 2>&1; then
    excerpt=$(jq -c '
      def redact:
        if type == "object" then
          with_entries(
            if (.key | test("token|secret|password|api[-_]?key|authorization"; "i")) then
              .value = "<redacted>"
            else
              .value |= redact
            end
          )
        elif type == "array" then map(redact)
        else .
        end;
      redact
    ' "$response_file")
  else
    excerpt=$(tr '\r\n' ' ' < "$response_file" | sed -E \
      -e 's/(Bearer )[[:alnum:]_.-]+/\1<redacted>/g' \
      -e 's/("(token|secret|password|authorization|api[-_]?key)"[[:space:]]*:[[:space:]]*")[^"]*/\1<redacted>/Ig')
  fi

  printf 'Response excerpt: %.500s\n' "$excerpt"
}

record_failure() {
  local cause="$1"
  local attempts="$2"

  write_output summary "Gopher AI review failed: $cause"
  write_output file_count 0
  write_output has_issues false
  write_output api_failed true
  write_output api_status "$cause"
  write_output skip_reason "${cause}-retry-exhausted"

  {
    echo '## Gopher AI Code Review'
    echo
    echo "Review failed after $attempts attempts."
    echo
    echo "- Cause: \`$cause\`"
    echo "- Attempts: $attempts of $MAX_ATTEMPTS"
    echo
    echo 'No additional retry will occur. The failed review is actionable and the job will remain failed.'
  } > "$STATUS_DIR/status.md"
}

if [ -z "${GOPHER_AI_API_KEY:-}" ]; then
  write_output summary 'Gopher AI review failed: missing API key'
  write_output file_count 0
  write_output has_issues false
  write_output api_failed true
  write_output api_status missing-api-key
  write_output skip_reason missing-api-key
  {
    echo '## Gopher AI Code Review'
    echo
    echo 'Review failed because the Gopher AI API key is not configured.'
    echo
    echo 'No retry occurred because authentication is required before a request can be made.'
  } > "$STATUS_DIR/status.md"
  exit 1
fi

if [ ! -s "$GOPHER_AI_DIFF_PATH" ]; then
  write_output summary 'Gopher AI review failed: empty diff'
  write_output file_count 0
  write_output has_issues false
  write_output api_failed true
  write_output api_status empty-diff
  write_output skip_reason empty-diff
  {
    echo '## Gopher AI Code Review'
    echo
    echo 'Review failed because the pull request diff is empty.'
    echo
    echo 'No API retry occurred because the review request could not be created.'
  } > "$STATUS_DIR/status.md"
  exit 1
fi

jq -n --rawfile diff "$GOPHER_AI_DIFF_PATH" --arg focus "${GOPHER_AI_FOCUS:-}" \
  'if $focus == "" then {diff: $diff} else {diff: $diff, focus: $focus} end' > "$PAYLOAD_FILE"

case "$GOPHER_AI_API_URL" in
  *\?*format=*) REVIEW_URL=$(printf '%s\n' "$GOPHER_AI_API_URL" | sed -E 's/([?&])format=[^&]*/\1format=github/') ;;
  *\?*) REVIEW_URL="${GOPHER_AI_API_URL}&format=github" ;;
  *) REVIEW_URL="${GOPHER_AI_API_URL}?format=github" ;;
esac

failure_cause=""
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  curl_status=0
  : > "$RESPONSE_FILE"
  set +e
  http_status=$(curl -sS \
    --output "$RESPONSE_FILE" \
    --write-out '%{http_code}' \
    -X POST "$REVIEW_URL" \
    -H "Authorization: Bearer $GOPHER_AI_API_KEY" \
    -H 'Content-Type: application/json' \
    --data-binary "@$PAYLOAD_FILE")
  curl_status=$?
  set -e

  if [ "$curl_status" -ne 0 ]; then
    failure_cause="api-request-failed"
  elif [ "$http_status" != "200" ]; then
    failure_cause="http-$http_status"
  elif ! jq -e . "$RESPONSE_FILE" >/dev/null 2>&1; then
    failure_cause="invalid-json"
  elif ! jq -e '
    type == "object" and
    (.summary | type == "string" and length > 0) and
    (.file_count | type == "number" and floor == . and . >= 0) and
    (.issues | type == "array")
  ' "$RESPONSE_FILE" >/dev/null 2>&1; then
    failure_cause="invalid-response-schema"
  else
    summary=$(jq -r '.summary' "$RESPONSE_FILE")
    file_count=$(jq -r '.file_count' "$RESPONSE_FILE")
    issue_count=$(jq -r '.issues | length' "$RESPONSE_FILE")
    has_issues=false
    if [ "$issue_count" -gt 0 ]; then
      has_issues=true
    fi

    write_output summary "$summary"
    write_output file_count "$file_count"
    write_output has_issues "$has_issues"
    write_output api_failed false
    write_output api_status 200
    write_output skip_reason ""
    {
      echo '## Gopher AI Code Review'
      echo
      echo 'Review completed.'
      echo
      echo "- Summary: $summary"
      echo "- Files reviewed: $file_count"
      echo "- Findings returned: $issue_count"
    } > "$STATUS_DIR/status.md"
    exit 0
  fi

  echo "::warning::Gopher AI review attempt $attempt of $MAX_ATTEMPTS failed: $failure_cause"
  if [ -s "$RESPONSE_FILE" ]; then
    redacted_response_excerpt "$RESPONSE_FILE"
  else
    echo 'Response excerpt: <empty>'
  fi

  if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
    echo 'Retrying once.'
    if [ "$RETRY_DELAY_SECONDS" != "0" ]; then
      sleep "$RETRY_DELAY_SECONDS"
    fi
  fi
  attempt=$((attempt + 1))
done

record_failure "$failure_cause" "$MAX_ATTEMPTS"
exit 1
