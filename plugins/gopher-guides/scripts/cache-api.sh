#!/bin/bash
# Cache wrapper for Gopher Guides API calls
# Usage: cache-api.sh <endpoint> <json-data>
#
# Caches responses under the user's cache directory
# TTL: 24h for practices/examples, 1h for audit/review
#
# Examples:
#   cache-api.sh practices '{"topic": "error handling"}'
#   cache-api.sh audit '{"code": "...", "focus": "error-handling"}'

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENDPOINT="${1:-}"
JSON_DATA="${2:-}"
CACHE_FILE="${GOPHER_GUIDES_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gopher-ai/gopher-guides-cache.json}"

if [ -z "$ENDPOINT" ] || [ -z "$JSON_DATA" ]; then
  echo "Usage: cache-api.sh <endpoint> <json-data>" >&2
  exit 1
fi

if [ -z "${GOPHER_GUIDES_API_KEY:-}" ]; then
  echo "Error: GOPHER_GUIDES_API_KEY is not set" >&2
  exit 1
fi

# Determine TTL based on endpoint (seconds)
case "$ENDPOINT" in
  practices|examples)
    TTL=86400  # 24 hours
    ;;
  audit|review)
    TTL=3600   # 1 hour
    ;;
  *)
    TTL=3600   # Default: 1 hour
    ;;
esac

# Create cache dir
mkdir -p "$(dirname "$CACHE_FILE")"
CACHE_EPOCH=$(/bin/bash "$SCRIPT_DIR/cache-mutate.sh" epoch "$CACHE_FILE")

# Generate cache key from endpoint + data
hash_input() {
  if command -v sha256sum &>/dev/null; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v openssl &>/dev/null; then
    openssl dgst -sha256 -r | cut -d' ' -f1
  else
    # Fallback: use raw input as key (no hashing)
    cat | tr -dc 'a-zA-Z0-9_-' | cut -c1-64
  fi
}
CACHE_KEY=$(printf '%s:%s' "$ENDPOINT" "$JSON_DATA" | hash_input)

# Check cache
if [ -f "$CACHE_FILE" ]; then
  CACHED=$(jq -r --arg key "$CACHE_KEY" '.[$key] // empty' "$CACHE_FILE" 2>/dev/null || true)
  if [ -n "$CACHED" ]; then
    CACHED_AT=$(echo "$CACHED" | jq -r '.cached_at // 0')
    NOW=$(date +%s)
    AGE=$((NOW - CACHED_AT))
    if [ "$AGE" -lt "$TTL" ]; then
      # Cache hit - return cached response
      echo "$CACHED" | jq -r '.response'
      exit 0
    fi
  fi
fi

# Cache miss - make API call
API_URL="https://gopherguides.com/api/gopher-ai/${ENDPOINT}"

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$JSON_DATA" \
  "$API_URL")

# Check if response is valid JSON
if ! echo "$RESPONSE" | jq . >/dev/null 2>&1; then
  echo "$RESPONSE"
  exit 1
fi

# Store in cache
NOW=$(date +%s)
CACHE_ENTRY=$(jq -n --arg resp "$RESPONSE" --argjson ts "$NOW" --arg ep "$ENDPOINT" \
  '{response: $resp, cached_at: $ts, endpoint: $ep}')

printf '%s\n' "$CACHE_ENTRY" |
  /bin/bash "$SCRIPT_DIR/cache-lock.sh" "${CACHE_FILE}.lock" \
    /bin/bash "$SCRIPT_DIR/cache-mutate.sh" update "$CACHE_FILE" "$CACHE_KEY" "$CACHE_EPOCH"

echo "$RESPONSE"
