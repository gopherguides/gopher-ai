#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REVIEW_FLOW="$ROOT_DIR/plugins/llm-tools/lib/codex/review-flow.md"
REVIEW_LOOP="$ROOT_DIR/plugins/llm-tools/lib/review-loop/review-phase.md"
SHIP_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
COMPLETE_FALLBACK="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/phases.md"

assert_count() {
  local expected="$1"
  local pattern="$2"
  local file="$3"
  local actual

  actual=$(rg -c --fixed-strings "$pattern" "$file" || true)
  if [ "$actual" != "$expected" ]; then
    echo "FAILED: expected $expected occurrence(s) of '$pattern' in ${file#"$ROOT_DIR/"}, found $actual"
    exit 1
  fi
}

assert_count 2 'MODEL_CONFIG=(-c "review_model=$MODEL")' "$REVIEW_FLOW"
assert_count 1 'MODEL_CONFIG=(-c "review_model=$MODEL")' "$REVIEW_LOOP"
assert_count 1 'CODEX_REVIEW_MODEL_ARGS=(-c "review_model=$MODEL")' "$SHIP_REVIEW"

assert_count 2 'MODEL_CONFIG=()' "$REVIEW_FLOW"
assert_count 1 'MODEL_CONFIG=()' "$REVIEW_LOOP"
assert_count 1 'CODEX_REVIEW_MODEL_ARGS=()' "$SHIP_REVIEW"

if rg -n --fixed-strings -- '-c "model=$MODEL"' "$REVIEW_FLOW" "$REVIEW_LOOP" "$SHIP_REVIEW"; then
  echo "FAILED: native codex review path uses the normal model configuration key"
  exit 1
fi

if ! rg -q --fixed-strings 'CODEX_MODEL_ARGS=(-m "$MODEL")' "$SHIP_REVIEW"; then
  echo "FAILED: exhaustive codex exec custom-model override changed"
  exit 1
fi

if rg -n -- 'review --base.*(model|review_model)=' "$COMPLETE_FALLBACK"; then
  echo "FAILED: complete-issue default review fallback overrides a model"
  exit 1
fi

echo "All Codex review model tests passed."
