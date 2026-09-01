#!/bin/bash

set -euo pipefail

MODE="${1:-}"
CACHE_FILE="${2:-}"
CACHE_EPOCH_FILE="${CACHE_FILE}.epoch"
CACHE_TEMP=""
EPOCH_TEMP=""
LOCK_DIRECTORY="${GOPHER_GUIDES_CACHE_LOCK_DIRECTORY:-}"
LOCK_OWNER_FILE="${GOPHER_GUIDES_CACHE_LOCK_OWNER_FILE:-}"

cache_epoch() {
  local epoch
  epoch=$(cat "$CACHE_EPOCH_FILE" 2>/dev/null || true)
  case "$epoch" in
    ''|*[!0-9]*) epoch=0 ;;
  esac
  printf '%s\n' "$epoch"
}

cleanup_cache_mutation() {
  [ -z "$CACHE_TEMP" ] || rm -f "$CACHE_TEMP"
  [ -z "$EPOCH_TEMP" ] || rm -f "$EPOCH_TEMP"
  [ -z "$LOCK_OWNER_FILE" ] || rm -f -- "$LOCK_OWNER_FILE"
  [ -z "$LOCK_DIRECTORY" ] || rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
}

trap cleanup_cache_mutation EXIT
trap 'exit 1' HUP INT TERM

case "$MODE" in
  epoch)
    [ -n "$CACHE_FILE" ] || exit 1
    cache_epoch
    ;;
  update)
    CACHE_KEY="${3:?Cache key is required}"
    EXPECTED_EPOCH="${4:?Cache epoch is required}"
    CACHE_ENTRY=$(cat)
    [ "$(cache_epoch)" = "$EXPECTED_EPOCH" ] || exit 0
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
    ;;
  clear)
    [ -n "$CACHE_FILE" ] || exit 1
    EPOCH_TEMP=$(mktemp "${CACHE_EPOCH_FILE}.tmp.XXXXXX")
    printf '%s\n' "$(( $(cache_epoch) + 1 ))" > "$EPOCH_TEMP"
    mv "$EPOCH_TEMP" "$CACHE_EPOCH_FILE"
    EPOCH_TEMP=""
    rm -f -- "$CACHE_FILE"
    ;;
  *)
    echo "Usage: cache-mutate.sh <epoch|update|clear> <cache-file> [arguments...]" >&2
    exit 1
    ;;
esac
