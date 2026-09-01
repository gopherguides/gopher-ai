#!/bin/bash

set -euo pipefail

LOCK_FILE="${1:-}"
if [ -z "$LOCK_FILE" ] || [ "$#" -lt 2 ]; then
  echo "Usage: cache-lock.sh <lock-file> <command> [arguments...]" >&2
  exit 1
fi
shift

mkdir -p "$(dirname "$LOCK_FILE")"
LOCK_DIR="$(cd "$(dirname "$LOCK_FILE")" && pwd)"
LOCK_PATH="$LOCK_DIR/$(basename "$LOCK_FILE")"

if [ "${GOPHER_GUIDES_CACHE_LOCK_FORCE_PORTABLE:-false}" != true ]; then
  if command -v flock >/dev/null 2>&1; then
    exec flock -w 12 "$LOCK_PATH" "$@"
  fi

  if command -v lockf >/dev/null 2>&1; then
    exec lockf -t 12 "$LOCK_PATH" "$@"
  fi
fi

LOCK_DIRECTORY="${LOCK_PATH}.directory"
OWNER_FILE="$LOCK_DIRECTORY/owner.$$.$RANDOM.$RANDOM"

process_identity() {
  local identity
  identity=$(ps -p "$1" -o lstart= 2>/dev/null || true)
  printf '%s\n' "$identity" | awk '{$1=$1; print}'
}

lock_directory_is_old() {
  local age
  local modified
  local now
  if modified=$(stat -f %m "$LOCK_DIRECTORY" 2>/dev/null); then
    :
  elif modified=$(stat -c %Y "$LOCK_DIRECTORY" 2>/dev/null); then
    :
  else
    return 1
  fi
  now=$(date +%s)
  age=$((now - modified))
  [ "$age" -ge 2 ]
}

portable_owner_is_live() {
  local current_identity
  local owner_file="${1:?Owner file is required}"
  local owner_identity
  local owner_name
  local owner_pid
  owner_name="${owner_file##*/}"
  owner_pid="${owner_name#owner.}"
  owner_pid="${owner_pid%%.*}"
  case "$owner_pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$owner_pid" 2>/dev/null || return 1
  owner_identity=$(cat "$owner_file" 2>/dev/null || true)
  current_identity=$(process_identity "$owner_pid")
  [ -z "$owner_identity" ] || [ -z "$current_identity" ] ||
    [ "$owner_identity" = "$current_identity" ]
}

reclaim_portable_lock() {
  local owner_file
  local owner_files=()
  shopt -s nullglob
  owner_files=("$LOCK_DIRECTORY"/owner.*)
  shopt -u nullglob
  if [ "${#owner_files[@]}" -eq 0 ]; then
    lock_directory_is_old && rmdir "$LOCK_DIRECTORY" 2>/dev/null
    return 0
  fi
  for owner_file in "${owner_files[@]}"; do
    if ! portable_owner_is_live "$owner_file"; then
      rm -f -- "$owner_file"
    fi
  done
  rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
}

release_directory_lock() {
  rm -f -- "$OWNER_FILE"
  rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
}

owner_identity=$(process_identity "$$")
attempt=0
while true; do
  if mkdir "$LOCK_DIRECTORY" 2>/dev/null; then
    if printf '%s\n' "$owner_identity" 2>/dev/null > "$OWNER_FILE"; then
      shopt -s nullglob
      owner_files=("$LOCK_DIRECTORY"/owner.*)
      shopt -u nullglob
      if [ "${#owner_files[@]}" -eq 1 ] && [ "${owner_files[0]}" = "$OWNER_FILE" ]; then
        break
      fi
      release_directory_lock
    fi
  else
    reclaim_portable_lock
  fi
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 240 ]; then
    echo "Error: Timed out waiting for the Gopher Guides cache lock: $LOCK_DIRECTORY" >&2
    exit 1
  fi
  sleep 0.05
done

trap release_directory_lock EXIT
trap 'exit 1' HUP INT TERM
export GOPHER_GUIDES_CACHE_LOCK_DIRECTORY="$LOCK_DIRECTORY"
export GOPHER_GUIDES_CACHE_LOCK_OWNER_FILE="$OWNER_FILE"
exec "$@"
