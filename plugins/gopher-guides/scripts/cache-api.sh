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
LOCK_FILE="${CACHE_FILE}.lock"
LOCK_CANDIDATE="${LOCK_FILE}.$$"
RECLAIM_DIR="${LOCK_FILE}.reclaim"
LOCK_OWNER=""
LOCK_STALE_SECONDS=10
CACHE_TEMP=""

release_cache_lock() {
  if [ -n "$CACHE_TEMP" ]; then
    rm -f "$CACHE_TEMP"
  fi
  rm -f "$LOCK_CANDIDATE"
  if [ -n "$LOCK_OWNER" ] && [ -f "$LOCK_FILE" ] &&
     [ "$(cat "$LOCK_FILE" 2>/dev/null)" = "$LOCK_OWNER" ]; then
    rm -f "$LOCK_FILE"
  fi
}

cache_lock_owner() {
  printf '%s %s %s\n' "$$" "$(date +%s)" "$RANDOM"
}

cache_lock_is_abandoned() {
  local lock_age
  local lock_created
  local lock_owner
  local lock_pid
  local now
  lock_owner=$(cat "$LOCK_FILE" 2>/dev/null || true)
  lock_pid=${lock_owner%% *}
  case "$lock_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ "$lock_owner" != "$lock_pid" ] || return 0
  lock_created=${lock_owner#"$lock_pid "}
  lock_created=${lock_created%% *}
  case "$lock_created" in
    ''|*[!0-9]*) return 0 ;;
  esac
  kill -0 "$lock_pid" 2>/dev/null || return 0
  now=$(date +%s)
  lock_age=$((now - lock_created))
  [ "$lock_age" -lt 0 ] || [ "$lock_age" -ge "$LOCK_STALE_SECONDS" ]
}

reclaim_abandoned_cache_lock() {
  cache_lock_is_abandoned || return 1
  mkdir "$RECLAIM_DIR" 2>/dev/null || return 1
  if cache_lock_is_abandoned; then
    rm -f "$LOCK_FILE"
  fi
  rmdir "$RECLAIM_DIR" 2>/dev/null || true
}

acquire_cache_lock() {
  local attempt=0
  LOCK_OWNER=$(cache_lock_owner)
  printf '%s\n' "$LOCK_OWNER" > "$LOCK_CANDIDATE"
  while ! ln "$LOCK_CANDIDATE" "$LOCK_FILE" 2>/dev/null; do
    reclaim_abandoned_cache_lock || true
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 240 ]; then
      echo "Error: Timed out waiting for the Gopher Guides cache lock" >&2
      return 1
    fi
    sleep 0.05
  done
  rm -f "$LOCK_CANDIDATE"
}

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

acquire_cache_lock
trap release_cache_lock EXIT
trap 'exit 1' HUP INT TERM
CACHE_TEMP=$(mktemp "${CACHE_FILE}.tmp.XXXXXX")

if [ -f "$CACHE_FILE" ] && jq -e 'type == "object"' "$CACHE_FILE" >/dev/null 2>&1; then
  jq --arg key "$CACHE_KEY" --argjson entry "$CACHE_ENTRY" \
    '.[$key] = $entry' "$CACHE_FILE" > "$CACHE_TEMP"
else
  jq -n --arg key "$CACHE_KEY" --argjson entry "$CACHE_ENTRY" \
    '{($key): $entry}' > "$CACHE_TEMP"
fi
mv "$CACHE_TEMP" "$CACHE_FILE"
CACHE_TEMP=""
rm -f "$LOCK_FILE"
trap - EXIT HUP INT TERM

echo "$RESPONSE"
