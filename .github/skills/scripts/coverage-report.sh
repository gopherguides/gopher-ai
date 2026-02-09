#!/usr/bin/env bash
# coverage-report.sh — Generate Go test coverage report and identify gaps
# Usage: bash coverage-report.sh [minimum-coverage-percent]
#
# Ref: https://github.com/gopherguides/gopher-ai/issues/51

set -euo pipefail

if [ -z "${GOPHER_GUIDES_API_KEY:-}" ]; then
    echo "ERROR: GOPHER_GUIDES_API_KEY is not set."
    echo "Get your API key at: https://gopherguides.com"
    echo "Then: export GOPHER_GUIDES_API_KEY=\"your-key\""
    exit 1
fi

MINIMUM="${1:-80}"
COVERAGE_FILE="coverage.out"
EXIT_CODE=0

header() { printf "\n\033[1;34m══ %s ══\033[0m\n\n" "$1"; }
pass()   { printf "  \033[32m✅ %s\033[0m\n" "$1"; }
fail()   { printf "  \033[31m🔴 %s\033[0m\n" "$1"; }
warn()   { printf "  \033[33m🟡 %s\033[0m\n" "$1"; }

# ── Generate coverage ─────────────────────────────────────────────────
header "Running Tests with Coverage"

if ! go test -coverprofile="$COVERAGE_FILE" -covermode=atomic ./... 2>&1; then
    fail "Some tests failed"
    EXIT_CODE=1
fi

if [[ ! -f "$COVERAGE_FILE" ]]; then
    fail "Coverage file not generated"
    exit 1
fi

# ── Parse results ─────────────────────────────────────────────────────
header "Coverage by Package"

printf "  %-50s %s\n" "PACKAGE" "COVERAGE"
printf "  %-50s %s\n" "-------" "--------"

TOTAL_COVERAGE=""
while IFS= read -r line; do
    pkg=$(echo "$line" | awk '{print $1}')
    cov=$(echo "$line" | awk '{print $NF}')

    if [[ "$pkg" == "total:" ]]; then
        TOTAL_COVERAGE="$cov"
        continue
    fi

    # Strip % for comparison
    cov_num="${cov%\%}"
    if (( $(echo "$cov_num < $MINIMUM" | bc -l 2>/dev/null || echo 0) )); then
        printf "  \033[31m%-50s %s\033[0m\n" "$pkg" "$cov"
    elif (( $(echo "$cov_num < 100" | bc -l 2>/dev/null || echo 0) )); then
        printf "  \033[33m%-50s %s\033[0m\n" "$pkg" "$cov"
    else
        printf "  \033[32m%-50s %s\033[0m\n" "$pkg" "$cov"
    fi
done < <(go tool cover -func="$COVERAGE_FILE" 2>/dev/null | grep -E "^(total:|[a-z])")

# ── Uncovered functions ───────────────────────────────────────────────
header "Uncovered Functions (0.0%)"

UNCOVERED=$(go tool cover -func="$COVERAGE_FILE" 2>/dev/null | grep "0.0%" | grep -v "total:" || true)
if [[ -n "$UNCOVERED" ]]; then
    echo "$UNCOVERED" | while IFS= read -r line; do
        fail "$line"
    done
else
    pass "No completely uncovered functions"
fi

# ── Missing test files ────────────────────────────────────────────────
header "Missing Test Files"

MISSING=0
while IFS= read -r gofile; do
    dir=$(dirname "$gofile")
    base=$(basename "$gofile" .go)
    if [[ ! -f "${dir}/${base}_test.go" ]]; then
        warn "Missing: ${dir}/${base}_test.go"
        MISSING=$((MISSING + 1))
    fi
done < <(find . -name '*.go' ! -name '*_test.go' ! -path '*/vendor/*' ! -path '*/.git/*' -not -name 'doc.go')

if [[ $MISSING -eq 0 ]]; then
    pass "All source files have corresponding test files"
fi

# ── Summary ───────────────────────────────────────────────────────────
header "Summary"

echo "  Total coverage: ${TOTAL_COVERAGE:-unknown}"
echo "  Minimum target: ${MINIMUM}%"

if [[ -n "$TOTAL_COVERAGE" ]]; then
    TOTAL_NUM="${TOTAL_COVERAGE%\%}"
    if (( $(echo "$TOTAL_NUM >= $MINIMUM" | bc -l 2>/dev/null || echo 0) )); then
        pass "Coverage meets minimum threshold"
    else
        fail "Coverage ($TOTAL_COVERAGE) is below minimum (${MINIMUM}%)"
        EXIT_CODE=1
    fi
fi

# ── HTML report ───────────────────────────────────────────────────────
if [[ -f "$COVERAGE_FILE" ]]; then
    go tool cover -html="$COVERAGE_FILE" -o coverage.html 2>/dev/null && \
        echo "  📄 HTML report: coverage.html" || true
fi

# Cleanup
rm -f "$COVERAGE_FILE"

exit $EXIT_CODE
