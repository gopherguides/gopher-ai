#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cache-lock.sh"

CACHE_FILE="${GOPHER_GUIDES_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gopher-ai/gopher-guides-cache.json}"
LEGACY_CACHE_FILE="$PWD/.claude/gopher-guides-cache.json"

clear_cache_file() {
  local cache_file="${1:?Cache file is required}"
  mkdir -p "$(dirname "$cache_file")"
  cache_lock_configure "$cache_file"
  cache_lock_acquire
  trap cache_lock_release EXIT
  trap 'exit 1' HUP INT TERM
  cache_lock_begin_mutation
  rm -f -- "$cache_file"
  cache_lock_end_mutation
  cache_lock_release
  trap - EXIT HUP INT TERM
}

clear_cache_file "$CACHE_FILE"
printf 'Gopher Guides cache cleared: %s\n' "$CACHE_FILE"

if [ -z "${GOPHER_GUIDES_CACHE_FILE:-}" ] &&
   [ "$LEGACY_CACHE_FILE" != "$CACHE_FILE" ] &&
   [ -f "$LEGACY_CACHE_FILE" ]; then
  clear_cache_file "$LEGACY_CACHE_FILE"
  printf 'Legacy Gopher Guides cache cleared: %s\n' "$LEGACY_CACHE_FILE"
fi
