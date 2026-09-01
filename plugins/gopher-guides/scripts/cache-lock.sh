#!/bin/bash

CACHE_LOCK_FILE=""
CACHE_LOCK_CANDIDATE=""
CACHE_LOCK_RECLAIM_DIR=""
CACHE_LOCK_OWNER=""
CACHE_LOCK_HEARTBEAT_FILE=""
CACHE_LOCK_HEARTBEAT_TEMP=""
CACHE_LOCK_HEARTBEAT_PID=""
CACHE_LOCK_HEARTBEAT_STALE_SECONDS=5

cache_lock_configure() {
  local cache_file="${1:?Cache file is required}"
  CACHE_LOCK_FILE="${cache_file}.lock"
  CACHE_LOCK_CANDIDATE="${CACHE_LOCK_FILE}.$$"
  CACHE_LOCK_RECLAIM_DIR="${CACHE_LOCK_FILE}.reclaim"
  CACHE_LOCK_HEARTBEAT_FILE="${CACHE_LOCK_FILE}.heartbeat"
  CACHE_LOCK_HEARTBEAT_TEMP="${CACHE_LOCK_HEARTBEAT_FILE}.$$"
  CACHE_LOCK_OWNER=""
  CACHE_LOCK_HEARTBEAT_PID=""
}

cache_lock_release() {
  if [ -n "$CACHE_LOCK_HEARTBEAT_PID" ]; then
    kill "$CACHE_LOCK_HEARTBEAT_PID" 2>/dev/null || true
    wait "$CACHE_LOCK_HEARTBEAT_PID" 2>/dev/null || true
  fi
  rm -f "$CACHE_LOCK_CANDIDATE"
  if [ -n "$CACHE_LOCK_OWNER" ] && [ -f "$CACHE_LOCK_FILE" ] &&
     [ "$(cat "$CACHE_LOCK_FILE" 2>/dev/null)" = "$CACHE_LOCK_OWNER" ]; then
    rm -f "$CACHE_LOCK_HEARTBEAT_FILE" "$CACHE_LOCK_HEARTBEAT_TEMP"
    rm -f "$CACHE_LOCK_FILE"
  fi
  CACHE_LOCK_OWNER=""
  CACHE_LOCK_HEARTBEAT_PID=""
}

cache_lock_owner() {
  printf '%s %s %s\n' "$$" "$(date +%s)" "$RANDOM"
}

cache_lock_timestamp_is_recent() {
  local created_at="${1:?Timestamp is required}"
  local now
  local age
  now=$(date +%s)
  age=$((now - created_at))
  [ "$age" -lt 0 ] || [ "$age" -lt "$CACHE_LOCK_HEARTBEAT_STALE_SECONDS" ]
}

cache_lock_write_heartbeat() {
  printf '%s %s\n' "$CACHE_LOCK_OWNER" "$(date +%s)" > "$CACHE_LOCK_HEARTBEAT_TEMP"
  mv "$CACHE_LOCK_HEARTBEAT_TEMP" "$CACHE_LOCK_HEARTBEAT_FILE"
}

cache_lock_heartbeat_loop() {
  while [ -f "$CACHE_LOCK_FILE" ] &&
        [ "$(cat "$CACHE_LOCK_FILE" 2>/dev/null)" = "$CACHE_LOCK_OWNER" ]; do
    cache_lock_write_heartbeat || return 1
    sleep 1
  done
}

cache_lock_start_heartbeat() {
  cache_lock_write_heartbeat || return 1
  cache_lock_heartbeat_loop &
  CACHE_LOCK_HEARTBEAT_PID=$!
}

cache_lock_is_abandoned() {
  local heartbeat_at
  local heartbeat_created
  local heartbeat_extra
  local heartbeat_nonce
  local heartbeat_owner
  local heartbeat_pid
  local lock_created
  local lock_extra
  local lock_nonce
  local lock_owner
  local lock_pid
  lock_owner=$(cat "$CACHE_LOCK_FILE" 2>/dev/null || true)
  IFS=' ' read -r lock_pid lock_created lock_nonce lock_extra <<< "$lock_owner"
  case "$lock_pid" in
    ''|*[!0-9]*) return 0 ;;
  esac
  case "$lock_created" in
    ''|*[!0-9]*) return 0 ;;
  esac
  case "$lock_nonce" in
    ''|*[!0-9]*) return 0 ;;
  esac
  [ -z "$lock_extra" ] || return 0
  kill -0 "$lock_pid" 2>/dev/null || return 0
  cache_lock_timestamp_is_recent "$lock_created" && return 1
  heartbeat_owner=$(cat "$CACHE_LOCK_HEARTBEAT_FILE" 2>/dev/null || true)
  IFS=' ' read -r heartbeat_pid heartbeat_created heartbeat_nonce heartbeat_at heartbeat_extra <<< "$heartbeat_owner"
  [ -z "$heartbeat_extra" ] || return 0
  [ "$heartbeat_pid" = "$lock_pid" ] || return 0
  [ "$heartbeat_created" = "$lock_created" ] || return 0
  [ "$heartbeat_nonce" = "$lock_nonce" ] || return 0
  case "$heartbeat_at" in
    ''|*[!0-9]*) return 0 ;;
  esac
  cache_lock_timestamp_is_recent "$heartbeat_at" && return 1
  return 0
}

cache_lock_reclaim_abandoned() {
  local abandoned_owner
  local abandoned_pid
  cache_lock_is_abandoned || return 1
  mkdir "$CACHE_LOCK_RECLAIM_DIR" 2>/dev/null || return 1
  if cache_lock_is_abandoned; then
    abandoned_owner=$(cat "$CACHE_LOCK_FILE" 2>/dev/null || true)
    abandoned_pid=${abandoned_owner%% *}
    rm -f "$CACHE_LOCK_HEARTBEAT_FILE" "${CACHE_LOCK_HEARTBEAT_FILE}.${abandoned_pid}"
    rm -f "$CACHE_LOCK_FILE"
  fi
  rmdir "$CACHE_LOCK_RECLAIM_DIR" 2>/dev/null || true
}

cache_lock_acquire() {
  local attempt=0
  CACHE_LOCK_OWNER=$(cache_lock_owner) || return 1
  printf '%s\n' "$CACHE_LOCK_OWNER" > "$CACHE_LOCK_CANDIDATE"
  while ! ln "$CACHE_LOCK_CANDIDATE" "$CACHE_LOCK_FILE" 2>/dev/null; do
    cache_lock_reclaim_abandoned || true
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 240 ]; then
      rm -f "$CACHE_LOCK_CANDIDATE"
      echo "Error: Timed out waiting for the Gopher Guides cache lock" >&2
      return 1
    fi
    sleep 0.05
  done
  rm -f "$CACHE_LOCK_CANDIDATE"
  if ! cache_lock_start_heartbeat; then
    cache_lock_release
    echo "Error: Unable to start the Gopher Guides cache lock heartbeat" >&2
    return 1
  fi
}
