#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECTOR="$ROOT_DIR/plugins/go-workflow/scripts/select-ollama-model.sh"
LOCAL_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-ship-ollama.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $1"
  exit 1
}

run_fixture() {
  local ps_exit="$1"
  local list_exit="$2"
  local fixture="$3"
  local output_file="$4"
  local error_file="$5"

  mkdir -p "$TEST_ROOT/bin"
  cat > "$TEST_ROOT/bin/ollama" <<EOF
#!/bin/bash
if [ "\$1" = "ps" ]; then
  exit $ps_exit
fi
if [ "\$1" = "list" ]; then
  printf '%s' '$fixture'
  exit $list_exit
fi
exit 99
EOF
  chmod +x "$TEST_ROOT/bin/ollama"

  PATH="$TEST_ROOT/bin:$PATH" "$SELECTOR" >"$output_file" 2>"$error_file"
}

echo "=== Ship Ollama Model Tests ==="

run_fixture 0 0 $'NAME ID SIZE MODIFIED\nllama3:latest abc 4GB today\nQwen2.5-Coder:7b def 5GB today\ndeepseek-code:latest ghi 6GB today\n' "$TEST_ROOT/output" "$TEST_ROOT/error"
[ "$(cat "$TEST_ROOT/output")" = "Qwen2.5-Coder:7b" ] || fail "first code-oriented model was not selected"

run_fixture 0 0 $'NAME ID SIZE MODIFIED\nllama3:latest abc 4GB today\nmistral:latest def 5GB today\n' "$TEST_ROOT/output" "$TEST_ROOT/error"
[ "$(cat "$TEST_ROOT/output")" = "llama3:latest" ] || fail "first installed fallback model was not selected"

if run_fixture 0 0 $'NAME ID SIZE MODIFIED\n' "$TEST_ROOT/output" "$TEST_ROOT/error"; then
  fail "empty model list succeeded"
fi
grep -q "No Ollama models are installed" "$TEST_ROOT/error" || fail "empty model guidance missing"

if run_fixture 1 0 '' "$TEST_ROOT/output" "$TEST_ROOT/error"; then
  fail "stopped server succeeded"
fi
grep -q "Ollama server is not running" "$TEST_ROOT/error" || fail "stopped server guidance missing"

if run_fixture 0 1 'connection reset' "$TEST_ROOT/output" "$TEST_ROOT/error"; then
  fail "failed model listing succeeded"
fi
grep -q "Unable to list installed Ollama models" "$TEST_ROOT/error" || fail "model-list failure guidance missing"

if grep -q "ollama run codellama" "$LOCAL_REVIEW"; then
  fail "hardcoded Ollama model remains in ship review"
fi
grep -q "ollama run \"\\\$OLLAMA_MODEL\"" "$LOCAL_REVIEW" || fail "resolved model is not used for Ollama runs"
grep -q "same persisted model" "$LOCAL_REVIEW" || fail "Ollama run retry does not preserve the selected model"
grep -q "Retry.*Debug / Fix.*Use agent-based review.*Abort" "$LOCAL_REVIEW" || fail "model-selection failure has no recovery path"

echo "All ship Ollama model tests passed."
