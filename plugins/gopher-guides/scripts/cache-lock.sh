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

if command -v flock >/dev/null 2>&1; then
  exec flock -w 12 "$LOCK_PATH" "$@"
fi

if command -v lockf >/dev/null 2>&1; then
  exec lockf -t 12 "$LOCK_PATH" "$@"
fi

echo "Error: Gopher Guides cache locking requires flock or lockf" >&2
exit 1
