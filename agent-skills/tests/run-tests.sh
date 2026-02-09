#!/usr/bin/env bash
# run-tests.sh — Validate agent skills structure, scripts, and configuration
# Usage: bash agent-skills/tests/run-tests.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PASS=0
FAIL=0

pass() { printf "  \033[32mPASS\033[0m %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL + 1)); }

header() { printf "\n\033[1;34m── %s ──\033[0m\n\n" "$1"; }

# ── SKILL.md Validation ──────────────────────────────────────────────

header "SKILL.md Validation"

for skill_dir in "$ROOT_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    skill_file="$skill_dir/SKILL.md"

    if [[ ! -f "$skill_file" ]]; then
        fail "$skill_name: missing SKILL.md"
        continue
    fi

    # Line count < 500
    lines=$(wc -l < "$skill_file")
    if [[ $lines -ge 500 ]]; then
        fail "$skill_name: $lines lines (max 500)"
    else
        pass "$skill_name: $lines lines"
    fi

    # Frontmatter name matches directory
    name=$(sed -n '/^---$/,/^---$/p' "$skill_file" | grep '^name:' | awk '{print $2}')
    if [[ "$name" == "$skill_name" ]]; then
        pass "$skill_name: name matches directory"
    else
        fail "$skill_name: frontmatter name '$name' != directory '$skill_name'"
    fi

    # Has description
    if grep -q '^description:' "$skill_file"; then
        pass "$skill_name: has description"
    else
        fail "$skill_name: missing description"
    fi

    # No hard API key gate
    if grep -q "Do not proceed without a valid API key" "$skill_file"; then
        fail "$skill_name: contains hard API key gate"
    else
        pass "$skill_name: no hard API key gate"
    fi
done

# ── Configuration Validation ─────────────────────────────────────────

header "Configuration Validation"

HAS_PYYAML=false
if python3 -c "import yaml" 2>/dev/null; then
    HAS_PYYAML=true
fi

if [[ "$HAS_PYYAML" == "true" ]]; then
    if python3 -c "import yaml; yaml.safe_load(open('$ROOT_DIR/config/severity.yaml'))" 2>/dev/null; then
        pass "severity.yaml: valid YAML"
    else
        fail "severity.yaml: invalid YAML"
    fi
else
    # Fallback: basic structure check when PyYAML is not installed
    if grep -q '^defaults:' "$ROOT_DIR/config/severity.yaml" && \
       grep -q '^categories:' "$ROOT_DIR/config/severity.yaml" && \
       grep -q '^score_weights:' "$ROOT_DIR/config/severity.yaml"; then
        pass "severity.yaml: basic structure valid (PyYAML not installed, skipped full parse)"
    else
        fail "severity.yaml: missing expected top-level keys"
    fi
fi

# Check score weights sum to 100
if [[ "$HAS_PYYAML" == "true" ]]; then
    SUM=$(python3 -c "
import yaml
with open('$ROOT_DIR/config/severity.yaml') as f:
    d = yaml.safe_load(f)
print(sum(d.get('score_weights', {}).values()))
" 2>/dev/null || echo "0")
    if [[ "$SUM" == "100" ]]; then
        pass "severity.yaml: score_weights sum to 100"
    else
        fail "severity.yaml: score_weights sum to $SUM (expected 100)"
    fi
else
    # Fallback: sum weights with awk
    SUM=$(awk '/^score_weights:/{found=1;next} found && /^[a-z]/{exit} found && /^  [a-z]/{split($0,a,": ");s+=a[2]} END{print s+0}' "$ROOT_DIR/config/severity.yaml")
    if [[ "$SUM" == "100" ]]; then
        pass "severity.yaml: score_weights sum to 100 (awk)"
    else
        fail "severity.yaml: score_weights sum to $SUM (expected 100)"
    fi
fi

# ── Script Validation ────────────────────────────────────────────────

header "Script Validation"

for script in "$ROOT_DIR"/scripts/*.sh; do
    name=$(basename "$script")

    # Scripts are executable or at least valid bash
    if bash -n "$script" 2>/dev/null; then
        pass "$name: valid bash syntax"
    else
        fail "$name: bash syntax error"
    fi

    # No hard API key exit (except as optional check)
    if grep -q 'exit 1' "$script" && grep -B2 'exit 1' "$script" | grep -q 'GOPHER_GUIDES_API_KEY'; then
        fail "$name: hard-exits on missing API key"
    else
        pass "$name: no hard API key gate"
    fi
done

# audit.sh has --yes flag
if grep -q '\-\-yes\|-y)' "$ROOT_DIR/scripts/audit.sh"; then
    pass "audit.sh: supports --yes flag"
else
    fail "audit.sh: missing --yes flag"
fi

# install.sh references agent-skills/ not .github/skills/
if grep -q 'agent-skills' "$ROOT_DIR/scripts/install.sh"; then
    pass "install.sh: references agent-skills/ source"
else
    fail "install.sh: still references old .github/skills/ path"
fi

# ── Demo Repo Validation ────────────────────────────────────────────

header "Demo Repo Validation"

DEMO_DIR="$ROOT_DIR/examples/demo-repo"

if [[ -f "$DEMO_DIR/go.mod" ]]; then
    pass "demo-repo: has go.mod"
else
    fail "demo-repo: missing go.mod"
fi

if [[ -f "$DEMO_DIR/main.go" ]]; then
    pass "demo-repo: has main.go"
else
    fail "demo-repo: missing main.go"
fi

if [[ -f "$DEMO_DIR/main_test.go" ]]; then
    pass "demo-repo: has main_test.go"
else
    fail "demo-repo: missing main_test.go"
fi

# No // BUG: comments (should be // Issue:)
if grep -q '// BUG:' "$DEMO_DIR/main.go" 2>/dev/null; then
    fail "demo-repo: main.go still has // BUG: comments"
else
    pass "demo-repo: uses // Issue: comments"
fi

# Makefile uses variable for scripts path
if grep -q 'SKILLS_SCRIPTS' "$DEMO_DIR/Makefile" 2>/dev/null; then
    pass "demo-repo: Makefile uses SKILLS_SCRIPTS variable"
else
    fail "demo-repo: Makefile has hardcoded script paths"
fi

# ── References ───────────────────────────────────────────────────────

header "References"

if [[ -f "$ROOT_DIR/references/api-usage.md" ]]; then
    pass "api-usage.md: exists"
else
    fail "api-usage.md: missing"
fi

# ── Summary ──────────────────────────────────────────────────────────

header "Summary"

echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
    printf "  \033[31m%d test(s) failed\033[0m\n" "$FAIL"
    exit 1
else
    printf "  \033[32mAll tests passed\033[0m\n"
    exit 0
fi
