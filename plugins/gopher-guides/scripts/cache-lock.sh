#!/bin/bash

CACHE_LOCK_FILE=""
CACHE_LOCK_CANDIDATE=""
CACHE_LOCK_RECLAIM_DIR=""
CACHE_LOCK_OWNER=""
CACHE_LOCK_STALE_SECONDS=10

cache_lock_configure() {
  local cache_file="${1:?Cache file is required}"
  CACHE_LOCK_FILE="${cache_file}.lock"
  CACHE_LOCK_CANDIDATE="${CACHE_LOCK_FILE}.$$"
  CACHE_LOCK_RECLAIM_DIR="${CACHE_LOCK_FILE}.reclaim"
  CACHE_LOCK_OWNER=""
}

cache_lock_release() {
  rm -f "$CACHE_LOCK_CANDIDATE"
  if [ -n "$CACHE_LOCK_OWNER" ] && [ -f "$CACHE_LOCK_FILE" ] &&
     [ "$(cat "$CACHE_LOCK_FILE" 2>/dev/null)" = "$CACHE_LOCK_OWNER" ]; then
    rm -f "$CACHE_LOCK_FILE"
  fi
  CACHE_LOCK_OWNER=""
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
  lock_owner=$(cat "$CACHE_LOCK_FILE" 2>/dev/null || true)
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
  [ "$lock_age" -lt 0 ] || [ "$lock_age" -ge "$CACHE_LOCK_STALE_SECONDS" ]
}

cache_lock_reclaim_abandoned() {
  cache_lock_is_abandoned || return 1
  mkdir "$CACHE_LOCK_RECLAIM_DIR" 2>/dev/null || return 1
  if cache_lock_is_abandoned; then
    rm -f "$CACHE_LOCK_FILE"
  fi
  rmdir "$CACHE_LOCK_RECLAIM_DIR" 2>/dev/null || true
}

cache_lock_acquire() {
  local attempt=0
  CACHE_LOCK_OWNER=$(cache_lock_owner)
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
}
