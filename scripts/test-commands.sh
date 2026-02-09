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

echo -n "Command files have valid YAML frontmatter... "
if [ $ERRORS -gt 0 ]; then
  echo "FAIL ($ERRORS of $TOTAL)"
  printf "$INVALID\n"
else
  echo "OK ($TOTAL commands)"
fi

echo ""
if [ $ERRORS -gt 0 ]; then
  echo "FAILED: $ERRORS command file(s) have issues"
  exit 1
else
  echo "All command tests passed."
fi
