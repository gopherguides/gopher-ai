#!/bin/bash
set -euo pipefail

GEMINI_DIR="${1:?usage: validate-gemini-extensions.sh <gemini-dist-dir>}"
ERRORS=0

if grep -RInE '\$\{?CLAUDE_PLUGIN_ROOT\}?' "$GEMINI_DIR" 2>/dev/null; then
  echo "Gemini artifacts contain unresolved CLAUDE_PLUGIN_ROOT references" >&2
  ERRORS=$((ERRORS + 1))
fi

for extension_dir in "$GEMINI_DIR"/gopher-ai-*; do
  [ -d "$extension_dir" ] || continue

  manifest="$extension_dir/gemini-extension.json"
  if [ ! -f "$manifest" ]; then
    echo "Missing Gemini extension manifest: $manifest" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi

  extension_name=$(jq -r '.name // empty' "$manifest")
  if [ -z "$extension_name" ]; then
    echo "Gemini extension manifest has no name: $manifest" >&2
    ERRORS=$((ERRORS + 1))
    continue
  fi

  root_reference="\$HOME/.gemini/extensions/$extension_name/"
  reference_pattern="\\\$HOME/\\.gemini/extensions/$extension_name/[A-Za-z0-9._/+*-]+"

  while IFS= read -r reference; do
    [ -n "$reference" ] || continue
    relative_path=${reference#"$root_reference"}

    if [[ "$relative_path" == *"*"* ]]; then
      if ! compgen -G "$extension_dir/$relative_path" >/dev/null; then
        echo "Missing Gemini extension glob target: $reference" >&2
        ERRORS=$((ERRORS + 1))
      fi
    elif [ ! -e "$extension_dir/$relative_path" ]; then
      echo "Missing Gemini extension asset: $reference" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -RhoE "$reference_pattern" "$extension_dir" 2>/dev/null | sort -u || true)
done

if [ "$ERRORS" -ne 0 ]; then
  exit 1
fi
