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
attempt=0
while ! mkdir "$LOCK_DIRECTORY" 2>/dev/null; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 240 ]; then
    echo "Error: Timed out waiting for the Gopher Guides cache lock: $LOCK_DIRECTORY" >&2
    exit 1
  fi
  sleep 0.05
done

release_directory_lock() {
  rmdir "$LOCK_DIRECTORY" 2>/dev/null || true
}

trap release_directory_lock EXIT
trap 'exit 1' HUP INT TERM
if "$@"; then
  status=0
else
  status=$?
fi
release_directory_lock
trap - EXIT HUP INT TERM
exit "$status"
