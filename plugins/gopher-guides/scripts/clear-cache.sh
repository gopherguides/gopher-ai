#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CACHE_FILE="${GOPHER_GUIDES_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gopher-ai/gopher-guides-cache.json}"
LEGACY_CACHE_FILE="$PWD/.claude/gopher-guides-cache.json"

clear_cache_file() {
  local cache_file="${1:?Cache file is required}"
  mkdir -p "$(dirname "$cache_file")"
  /bin/bash "$SCRIPT_DIR/cache-lock.sh" "${cache_file}.lock" \
    /bin/bash "$SCRIPT_DIR/cache-mutate.sh" clear "$cache_file"
}

clear_cache_file "$CACHE_FILE"
printf 'Gopher Guides cache cleared: %s\n' "$CACHE_FILE"

if [ -z "${GOPHER_GUIDES_CACHE_FILE:-}" ] &&
   [ "$LEGACY_CACHE_FILE" != "$CACHE_FILE" ] &&
   [ -f "$LEGACY_CACHE_FILE" ]; then
  clear_cache_file "$LEGACY_CACHE_FILE"
  printf 'Legacy Gopher Guides cache cleared: %s\n' "$LEGACY_CACHE_FILE"
fi
