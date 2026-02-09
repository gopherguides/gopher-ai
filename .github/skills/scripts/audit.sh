#!/usr/bin/env bash
# audit.sh — Full Go code quality audit
# Runs go vet + staticcheck + golangci-lint + Gopher Guides API audit
# Usage: bash audit.sh [path]
#
# Ref: https://github.com/gopherguides/gopher-ai/issues/51

set -euo pipefail

TARGET="${1:-.}/..."
REPORT=""
EXIT_CODE=0

header() { printf "\n\033[1;34m══ %s ══\033[0m\n\n" "$1"; }
pass()   { printf "  \033[32m✅ %s\033[0m\n" "$1"; }
fail()   { printf "  \033[31m🔴 %s\033[0m\n" "$1"; }
warn()   { printf "  \033[33m🟡 %s\033[0m\n" "$1"; }

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
    if golangci-lint run --max-issues-per-linter 0 --max-same-issues 0 "$TARGET" 2>&1; then
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
if [[ -n "${GOPHER_GUIDES_API_KEY:-}" ]]; then
    # Collect Go source files (limit to 50KB to stay within API limits)
    CODE=$(find "${1:-.}" -name '*.go' ! -name '*_test.go' ! -path '*/vendor/*' -exec cat {} + | head -c 50000)
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
        warn "API returned HTTP $HTTP_CODE — skipping"
    fi
else
    warn "GOPHER_GUIDES_API_KEY not set — skipping API audit"
    echo "  Set your key: export GOPHER_GUIDES_API_KEY=\"your-key\""
fi

# ── Summary ───────────────────────────────────────────────────────────
header "Summary"
if [[ $EXIT_CODE -eq 0 ]]; then
    pass "All local checks passed!"
else
    fail "Some checks failed — see above"
fi

exit $EXIT_CODE
