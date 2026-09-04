#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMP_BASE=${TMPDIR:-${TMP:-${TEMP:-/tmp}}}

if [ "$(uname -s)" = Darwin ]; then
  case "$TEMP_BASE/" in
    "$ROOT_DIR/.detent/tmp/"*)
      OUTPUT_DIR=$(mktemp -d "$TEMP_BASE/gopher-ai-go-tests.XXXXXX")
      trap 'rm -rf "$OUTPUT_DIR"' EXIT
      go test -c -o "$OUTPUT_DIR/" "$@"
      echo "Managed Darwin worker compiled Go tests without executing workspace binaries."
      exit 0
      ;;
  esac
fi

exec go test "$@"
