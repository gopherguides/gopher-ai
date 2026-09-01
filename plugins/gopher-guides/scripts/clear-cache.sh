#!/usr/bin/env bash

set -euo pipefail

CACHE_FILE="${GOPHER_GUIDES_CACHE_FILE:-${XDG_CACHE_HOME:-$HOME/.cache}/gopher-ai/gopher-guides-cache.json}"
LEGACY_CACHE_FILE="$PWD/.claude/gopher-guides-cache.json"

rm -f -- "$CACHE_FILE"
printf 'Gopher Guides cache cleared: %s\n' "$CACHE_FILE"

if [ -z "${GOPHER_GUIDES_CACHE_FILE:-}" ] &&
   [ "$LEGACY_CACHE_FILE" != "$CACHE_FILE" ] &&
   [ -f "$LEGACY_CACHE_FILE" ]; then
  rm -f -- "$LEGACY_CACHE_FILE"
  printf 'Legacy Gopher Guides cache cleared: %s\n' "$LEGACY_CACHE_FILE"
fi
