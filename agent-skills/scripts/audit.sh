#!/usr/bin/env bash
# audit.sh — Full Go code quality audit
# Runs go vet + staticcheck + golangci-lint + optional Gopher Guides API audit
# Usage: bash audit.sh [--yes|-y] [path]
#
# Ref: https://github.com/gopherguides/gopher-ai/issues/51

set -euo pipefail

header() { printf "\n\033[1;34m══ %s ══\033[0m\n\n" "$1"; }
pass()   { printf "  \033[32m✅ %s\033[0m\n" "$1"; }
fail()   { printf "  \033[31m🔴 %s\033[0m\n" "$1"; }
warn()   { printf "  \033[33m🟡 %s\033[0m\n" "$1"; }

AUTO_YES=false
PATH_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            AUTO_YES=true
            shift
            ;;
        -*)
            echo "Unknown flag: $1" >&2
            echo "Usage: bash audit.sh [--yes|-y] [path]" >&2
            exit 1
            ;;
        *)
            PATH_ARG="$1"
            shift
            ;;
    esac
done

WORK_DIR="${PATH_ARG:-.}"
if [[ -n "$PATH_ARG" && -d "$PATH_ARG" ]]; then
    cd "$PATH_ARG"
    WORK_DIR="."
fi
TARGET="$WORK_DIR/..."
EXIT_CODE=0

# ── go vet ────────────────────────────────────────────────────────────
header "go vet"
if go vet "$TARGET" 2>&1; then
    pass "go vet passed"
else
    fail "go vet found issues"
    EXIT_CODE=1
fi

# ── staticcheck ───────────────────────────────────────────────────────
header "staticcheck"
if command -v staticcheck &>/dev/null; then
    if staticcheck "$TARGET" 2>&1; then
        pass "staticcheck passed"
    else
        fail "staticcheck found issues"
        EXIT_CODE=1
    fi
else
    warn "staticcheck not installed — skipping (go install honnef.co/go/tools/cmd/staticcheck@latest)"
fi

# ── golangci-lint ─────────────────────────────────────────────────────
header "golangci-lint"
if command -v golangci-lint &>/dev/null; then
    if golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 "$WORK_DIR/..." 2>&1; then
        pass "golangci-lint passed"
    else
        fail "golangci-lint found issues"
        EXIT_CODE=1
    fi
else
    warn "golangci-lint not installed — skipping (brew install golangci-lint)"
fi

# ── Gopher Guides API audit ──────────────────────────────────────────
header "Gopher Guides API Audit"

if [[ -z "${GOPHER_GUIDES_API_KEY:-}" ]]; then
    echo "  Skipping API audit (set GOPHER_GUIDES_API_KEY for enhanced analysis)"
else
    SEARCH_DIR="$WORK_DIR"
    FILE_COUNT=$(find "$SEARCH_DIR" -name '*.go' ! -name '*_test.go' ! -path '*/vendor/*' | wc -l | tr -d ' ')
    BYTE_SIZE=$(find "$SEARCH_DIR" -name '*.go' ! -name '*_test.go' ! -path '*/vendor/*' -exec cat {} + 2>/dev/null | head -c 50000 | wc -c | tr -d ' ')

    PROCEED=true
    if [[ "$AUTO_YES" != "true" ]] && [[ -t 0 ]]; then
        echo "  Will send $FILE_COUNT Go source file(s) (~${BYTE_SIZE} bytes, max 50KB) to the Gopher Guides API."
        printf "  Continue? [y/N] "
        read -r CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            echo "  Skipped API audit."
            PROCEED=false
        fi
    fi

    if [[ "$PROCEED" == "true" ]]; then
        CODE=$(find "$SEARCH_DIR" -name '*.go' ! -name '*_test.go' ! -path '*/vendor/*' -exec cat {} + | head -c 50000)
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
            -H "Authorization: Bearer $GOPHER_GUIDES_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg code "$CODE" '{code: $code, focus: "audit"}')" \
            https://gopherguides.com/api/gopher-ai/audit 2>&1) || true

        HTTP_CODE=$(echo "$RESPONSE" | tail -1)
        BODY=$(echo "$RESPONSE" | sed '$d')

        if [[ "$HTTP_CODE" == "200" ]]; then
            echo "$BODY" | jq -r '.summary // "Analysis complete"' 2>/dev/null || echo "$BODY"
            SCORE=$(echo "$BODY" | jq -r '.score // "N/A"' 2>/dev/null || echo "N/A")
            pass "API audit complete — Score: $SCORE/100"
        else
            fail "API returned HTTP $HTTP_CODE"
            EXIT_CODE=1
        fi
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────
header "Summary"
if [[ $EXIT_CODE -eq 0 ]]; then
    pass "All local checks passed!"
else
    fail "Some checks failed — see above"
fi

exit $EXIT_CODE
