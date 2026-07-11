#!/bin/bash

set -euo pipefail

if ! ollama ps >/dev/null 2>&1; then
  echo "Ollama server is not running. Start it with: ollama serve" >&2
  exit 2
fi

MODEL_LIST=$(ollama list 2>&1) || {
  echo "Unable to list installed Ollama models: $MODEL_LIST" >&2
  exit 3
}

MODELS=$(printf '%s\n' "$MODEL_LIST" | awk 'NR > 1 && NF > 0 { print $1 }')
if [ -z "$MODELS" ]; then
  echo "No Ollama models are installed. Pull one first, for example: ollama pull qwen3-coder" >&2
  exit 4
fi

CODE_MODEL=$(printf '%s\n' "$MODELS" | awk 'tolower($0) ~ /(code|coder)/ { print; exit }')
if [ -n "$CODE_MODEL" ]; then
  printf '%s\n' "$CODE_MODEL"
else
  printf '%s\n' "$MODELS" | awk 'NR == 1 { print; exit }'
fi
