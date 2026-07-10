#!/bin/bash
# Verify all .md command files have valid YAML frontmatter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0

echo "=== Command File Tests ==="

# Find all command .md files
COMMAND_FILES=$(find "$ROOT_DIR/plugins" "$ROOT_DIR/shared" -path "*/commands/*.md" -type f 2>/dev/null | sort)
TOTAL=0
INVALID=""

for file in $COMMAND_FILES; do
  TOTAL=$((TOTAL + 1))
  REL_PATH="${file#$ROOT_DIR/}"

  # Check file starts with ---
  FIRST_LINE=$(head -1 "$file")
  if [ "$FIRST_LINE" != "---" ]; then
    INVALID="$INVALID\n  $REL_PATH (missing opening ---)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Check for closing ---
  # Find the second --- (closing frontmatter)
  CLOSING_LINE=$(awk 'NR>1 && /^---$/{print NR; exit}' "$file")
  if [ -z "$CLOSING_LINE" ]; then
    INVALID="$INVALID\n  $REL_PATH (missing closing ---)"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  # Extract frontmatter and check for description field
  FRONTMATTER=$(sed -n "2,$((CLOSING_LINE - 1))p" "$file")
  if ! echo "$FRONTMATTER" | grep -q 'description:'; then
    INVALID="$INVALID\n  $REL_PATH (missing description field)"
    ERRORS=$((ERRORS + 1))
    continue
  fi
done

echo -n "Codex fallback commands use the official package safely... "
UNSCOPED_CODEX=$(grep -RInE 'npx[^`]*codex' "$ROOT_DIR/plugins" | grep -v '@openai/codex' || true)
CODEX_COMMAND="$ROOT_DIR/plugins/llm-tools/commands/codex.md"
NONINTERACTIVE_CODEX_FILES=(
  "$ROOT_DIR/plugins/llm-tools/commands/review-loop.md"
  "$ROOT_DIR/plugins/llm-tools/commands/llm-compare.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
)
MISSING_INSTALLED_CHECK=""
for file in "${NONINTERACTIVE_CODEX_FILES[@]}"; do
  if ! grep -q 'command -v codex' "$file"; then
    MISSING_INSTALLED_CHECK="${file#"$ROOT_DIR"/}"
    break
  fi
done
MISSING_AUTH_GUIDANCE=""
AUTH_GUIDANCE_FILES=(
  "$ROOT_DIR/plugins/llm-tools/lib/review-loop/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/prerequisites.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/codex-fallback.md"
)
for file in "${AUTH_GUIDANCE_FILES[@]}"; do
  if ! grep -q 'ChatGPT sign-in or API-key authentication' "$file"; then
    MISSING_AUTH_GUIDANCE="${file#"$ROOT_DIR"/}"
    break
  fi
done

if [ -n "$UNSCOPED_CODEX" ]; then
  echo "FAIL (unscoped npm Codex invocation found)"
  echo "$UNSCOPED_CODEX"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_INSTALLED_CHECK" ]; then
  echo "FAIL (installed Codex preference missing from $MISSING_INSTALLED_CHECK)"
  ERRORS=$((ERRORS + 1))
elif grep -qE 'npx[^`]*@openai/codex' "${NONINTERACTIVE_CODEX_FILES[@]}"; then
  echo "FAIL (non-interactive workflow downloads Codex)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q 'CODEX_CMD="npx -y @openai/codex"' "$CODEX_COMMAND"; then
  echo "FAIL (accepted run-once fallback missing)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q '\*\*Abort\*\*.*without running Codex or downloading a package' "$CODEX_COMMAND"; then
  echo "FAIL (declined run-once behavior missing)"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_AUTH_GUIDANCE" ]; then
  echo "FAIL (Codex authentication guidance missing from $MISSING_AUTH_GUIDANCE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Command files have valid YAML frontmatter... "
if [ $ERRORS -gt 0 ]; then
  echo "FAIL ($ERRORS of $TOTAL)"
  printf "$INVALID\n"
else
  echo "OK ($TOTAL commands)"
fi

echo ""

echo -n "Gemini image defaults and request tiers are valid... "
GEMINI_IMAGE_DIR="$ROOT_DIR/plugins/llm-tools/skills/gemini-image"
GEMINI_COMMAND="$ROOT_DIR/plugins/llm-tools/commands/gemini-image.md"

if rg -q 'gemini-3\.1-flash-image-preview' "$GEMINI_IMAGE_DIR" "$GEMINI_COMMAND"; then
  echo "FAIL (retired preview model referenced)"
  ERRORS=$((ERRORS + 1))
else
  BUILD_BLOCK=$(mktemp /tmp/gemini-image-build-XXXXXX)
  awk '
    /^## Build Block/ { section=1 }
    section && /^```bash$/ { block=1; next }
    block && /^```$/ { exit }
    block { print }
  ' "$GEMINI_IMAGE_DIR/request-builder.md" > "$BUILD_BLOCK"

  DEFAULT_REQUEST=$(env -u GEMINI_MODEL -u GEMINI_SERVICE_TIER GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  UNSUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-3.1-flash-image GEMINI_SERVICE_TIER=priority GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  SUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=PRIORITY GEMINI_PROMPT=test bash "$BUILD_BLOCK")
  INVALID_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=express GEMINI_IMAGE_SIZE=4K GEMINI_PROMPT=test bash "$BUILD_BLOCK")

  if ! rg -q 'os.environ.get\("GEMINI_MODEL", "gemini-3\.1-flash-image"\)' "$GEMINI_IMAGE_DIR/request-builder.md"; then
    echo "FAIL (GA model is not the builder default)"
    ERRORS=$((ERRORS + 1))
  elif python3 - "$DEFAULT_REQUEST" "$UNSUPPORTED_REQUEST" "$SUPPORTED_REQUEST" "$INVALID_REQUEST" <<'PYEOF'
import json
import sys

with open(sys.argv[1]) as f:
    default_payload = json.load(f)
with open(sys.argv[2]) as f:
    unsupported_payload = json.load(f)
with open(sys.argv[3]) as f:
    supported_payload = json.load(f)
with open(sys.argv[4]) as f:
    invalid_payload = json.load(f)

assert "serviceTier" not in default_payload
assert "serviceTier" not in unsupported_payload
assert supported_payload["serviceTier"] == "priority"
assert "serviceTier" not in invalid_payload
assert "imageSize" not in invalid_payload["generationConfig"]["imageConfig"]
PYEOF
  then
    echo "OK"
  else
    echo "FAIL (generated serviceTier payload mismatch)"
    ERRORS=$((ERRORS + 1))
  fi

  rm -f "$BUILD_BLOCK" "$DEFAULT_REQUEST" "$UNSUPPORTED_REQUEST" "$SUPPORTED_REQUEST" "$INVALID_REQUEST"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS command file(s) have issues"
  exit 1
else
  echo "All command tests passed."
fi
