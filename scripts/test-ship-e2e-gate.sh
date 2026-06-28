#!/bin/bash
# Verify $ship treats missing UI E2E prerequisites as a blocking condition.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LOCAL_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
SHIP_SKILL="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
MERGE_DOC="$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"
STATE_FIELDS="$ROOT_DIR/plugins/go-workflow/lib/ship/state-fields.md"

ERRORS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

require_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if ! grep -qE "$pattern" "$file"; then
    fail "$label"
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  local label="$3"

  if grep -qE "$pattern" "$file"; then
    fail "$label"
  fi
}

echo "=== Ship E2E Gate Tests ==="

require_text "$LOCAL_REVIEW" "E2E PREREQUISITE MISSING" \
  "ship local review must name the missing-dev-server blocker"
require_text "$LOCAL_REVIEW" "e2e_result.*blocked" \
  "ship local review must persist blocked E2E state"
require_text "$LOCAL_REVIEW" "No merge" \
  "ship local review must explicitly stop before merge"
require_text "$SHIP_SKILL" "E2E may be reused only when" \
  "ship skill must not document --skip-coverage as unconditional E2E skip"
require_text "$SHIP_SKILL" "e2e_result=blocked" \
  "ship skill must document blocked E2E state in the top-level phase summary"
require_text "$SHIP_SKILL" "skipped only because the[[:space:]]*$" \
  "ship completion criteria must limit E2E skip to non-UI/no-web cases"
reject_text "$LOCAL_REVIEW" "If server fails to start within 30s.*skip to Step 8\\. Do NOT block shipping" \
  "ship local review still silently skips when dev server is missing"
reject_text "$LOCAL_REVIEW" "E2E failures are informational, NEVER block" \
  "ship local review still documents E2E failures as non-blocking"
reject_text "$SHIP_SKILL" "skip coverage \\+ e2e phases entirely" \
  "ship skill still says --skip-coverage skips E2E entirely"
reject_text "$SHIP_SKILL" "E2E smoke tests passed \\(or skipped .*[Mm]CP unavailable" \
  "ship completion criteria still allows MCP-unavailable E2E skip"

require_text "$MERGE_DOC" "e2e_result.*blocked" \
  "ship merge phase must read blocked E2E state"
require_text "$MERGE_DOC" "E2E PREREQUISITE MISSING" \
  "ship merge phase must stop on blocked E2E state"
require_text "$MERGE_DOC" "Verification partial" \
  "ship summary must avoid unqualified verification-complete wording for partial E2E"

require_text "$STATE_FIELDS" "blocked" \
  "ship state fields must document blocked E2E result"

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS ship E2E gate issue(s)"
  exit 1
fi

echo "All ship E2E gate tests passed."
