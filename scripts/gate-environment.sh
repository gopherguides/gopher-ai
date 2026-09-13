#!/bin/bash

if [ "$(uname -s)" = Darwin ]; then
  GATE_TOOL_DIR=$(mktemp -d "${TMPDIR:?}/gopher-ai-gate-tools-XXXXXX") || return 1
  ln -s /bin/bash "$GATE_TOOL_DIR/bash" || return 1
  for gate_tool in git python3; do
    gate_tool_path=""
    for gate_prefix in /opt/homebrew /usr/local; do
      if [ -x "$gate_prefix/bin/$gate_tool" ]; then
        gate_tool_path="$gate_prefix/bin/$gate_tool"
        break
      fi
    done
    if [ -z "$gate_tool_path" ]; then
      printf 'Gate requires Homebrew %s on macOS\n' "$gate_tool" >&2
      return 1
    fi
    ln -s "$gate_tool_path" "$GATE_TOOL_DIR/$gate_tool" || return 1
  done
  export PATH="$GATE_TOOL_DIR:$PATH"
  export TMP="$TMPDIR" TEMP="$TMPDIR"
  python3 -m venv "$GATE_TOOL_DIR/venv" || return 1
  export PATH="$GATE_TOOL_DIR/venv/bin:$PATH"
  export PIP_CACHE_DIR="$GATE_TOOL_DIR/pip-cache"
fi
