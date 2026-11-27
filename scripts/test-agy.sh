#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_AGY="$ROOT_DIR/dist/agy"

PASS=0
FAIL=0

pass() {
    echo "  PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  FAIL: $1" >&2
    FAIL=$((FAIL + 1))
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label (expected '$expected', got '$actual')"
    fi
}

echo "=== Antigravity (agy) Build, Install, and Hook Tests ==="

if [[ ! -d "$DIST_AGY/plugins" ]]; then
    echo "Building universal distribution first..."
    "$ROOT_DIR/scripts/build-universal.sh" >/dev/null
fi

# 1. Verify all 7 plugins built with plugin.json
expected_plugins=(
    gopher-ai-go-dev
    gopher-ai-go-web
    gopher-ai-go-workflow
    gopher-ai-gopher-guides
    gopher-ai-llm-tools
    gopher-ai-productivity
    gopher-ai-tailwind
)

for p in "${expected_plugins[@]}"; do
    if [[ -f "$DIST_AGY/plugins/$p/plugin.json" ]]; then
        pass "built $p/plugin.json"
    else
        fail "missing $DIST_AGY/plugins/$p/plugin.json"
    fi
done

if [[ -f "$DIST_AGY/plugins/gopher-ai-go-workflow/hooks.json" ]]; then
    pass "built gopher-ai-go-workflow/hooks.json"
else
    fail "missing gopher-ai-go-workflow/hooks.json"
fi

# 2. Validate with agy CLI if available
if command -v agy >/dev/null 2>&1; then
    for p in "${expected_plugins[@]}"; do
        if agy plugin validate "$DIST_AGY/plugins/$p" >/dev/null 2>&1; then
            pass "agy plugin validate $p"
        else
            fail "agy plugin validate $p failed"
            agy plugin validate "$DIST_AGY/plugins/$p" || true
        fi
    done
else
    echo "  SKIP: agy CLI not installed on PATH"
fi

# 3. Test isolated install, token substitution, preservation of other plugins, and uninstall
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

TEST_CONFIG="$TMP_ROOT/config"
mkdir -p "$TEST_CONFIG/plugins/other-plugin"
printf '{"name":"other-plugin"}\n' > "$TEST_CONFIG/plugins/other-plugin/plugin.json"

"$ROOT_DIR/scripts/install-agy.sh" --source "$DIST_AGY" --config-dir "$TEST_CONFIG" --no-cleanup-legacy >/dev/null

if [[ -f "$TEST_CONFIG/plugins/other-plugin/plugin.json" ]]; then
    pass "install preserves non-gopher-ai plugins"
else
    fail "install removed non-gopher-ai plugin"
fi

if [[ -f "$TEST_CONFIG/plugins/gopher-ai-go-workflow/skills/start-issue/SKILL.md" ]]; then
    pass "installed start-issue skill"
else
    fail "missing installed start-issue skill"
fi

if grep -qE '^disable-model-invocation:' "$TEST_CONFIG/plugins/gopher-ai-go-workflow/skills/start-issue/SKILL.md" "$TEST_CONFIG/plugins/gopher-ai-go-workflow/skills/ship/SKILL.md"; then
    fail "disable-model-invocation was not stripped from agy workflow skills"
else
    pass "workflow skills are model-discoverable in agy (disable-model-invocation stripped)"
fi

if grep -rqF "__GOPHER_AI_AGY_PLUGIN_ROOT__" "$TEST_CONFIG/plugins/gopher-ai-"*; then
    fail "unreplaced __GOPHER_AI_AGY_PLUGIN_ROOT__ token found after install"
else
    pass "all plugin root tokens replaced after install"
fi

EXPECTED_WORKFLOW_ROOT="$(cd "$TEST_CONFIG/plugins/gopher-ai-go-workflow" && pwd -P)"
if grep -qF "$EXPECTED_WORKFLOW_ROOT/lib/start-issue/setup.md" "$TEST_CONFIG/plugins/gopher-ai-go-workflow/skills/start-issue/SKILL.md"; then
    pass "start-issue SKILL.md resolves absolute installed plugin root"
else
    fail "start-issue SKILL.md missing resolved plugin root"
fi

# 4. Test agy hook contracts
PRE_HOOK="$TEST_CONFIG/plugins/gopher-ai-go-workflow/hooks/pre-tool-use.sh"
POST_HOOK="$TEST_CONFIG/plugins/gopher-ai-go-workflow/hooks/post-tool-use.sh"
STOP_HOOK="$TEST_CONFIG/plugins/gopher-ai-go-workflow/hooks/stop-hook.sh"

# PreToolUse allow
pre_allow_out=$(printf '%s\n' '{"conversationId":"conv-1","hookEventName":"PreToolUse","cwd":"/tmp","toolCall":{"id":"1","name":"run_command","args":{"CommandLine":"echo hello"}}}' | "$PRE_HOOK")
assert_eq "$(printf '%s' "$pre_allow_out" | jq -r '.decision')" "allow" "agy PreToolUse allow returns decision=allow"

# PreToolUse deny on dirty repo git tag
DIRTY_REPO="$TMP_ROOT/dirty-repo"
mkdir -p "$DIRTY_REPO"
git -C "$DIRTY_REPO" init -q
git -C "$DIRTY_REPO" config user.email "test@example.com"
git -C "$DIRTY_REPO" config user.name "Test"
printf 'hello\n' > "$DIRTY_REPO/a.txt"
git -C "$DIRTY_REPO" add a.txt
git -C "$DIRTY_REPO" commit -q -m "init"
printf 'dirty\n' >> "$DIRTY_REPO/a.txt"

pre_deny_out=$(jq -cn --arg cwd "$DIRTY_REPO" '{conversationId:"conv-1",hookEventName:"PreToolUse",cwd:$cwd,toolCall:{id:"2",name:"run_command",args:{CommandLine:"git tag v1.0.0"}}}' | "$PRE_HOOK")
assert_eq "$(printf '%s' "$pre_deny_out" | jq -r '.decision')" "deny" "agy PreToolUse deny returns decision=deny on dirty git tag"

# PostToolUse returns {}
post_out=$(printf '%s\n' '{"conversationId":"conv-1","hookEventName":"PostToolUse","cwd":"/tmp","toolCall":{"id":"1","name":"run_command","args":{"CommandLine":"echo hello"}}}' | "$POST_HOOK")
assert_eq "$post_out" "{}" "agy PostToolUse returns {}"

# Stop returns {} when no loop active
stop_allow_out=$(jq -cn --arg cwd "$DIRTY_REPO" '{conversationId:"conv-1",hookEventName:"Stop",cwd:$cwd,terminationReason:"NO_TOOL_CALL",continuationActive:false}' | "$STOP_HOOK")
assert_eq "$stop_allow_out" "{}" "agy Stop returns {} when no active loop"

# Stop returns {} when continuationActive is true
stop_cont_out=$(jq -cn --arg cwd "$DIRTY_REPO" '{conversationId:"conv-1",hookEventName:"Stop",cwd:$cwd,terminationReason:"NO_TOOL_CALL",continuationActive:true}' | "$STOP_HOOK")
assert_eq "$stop_cont_out" "{}" "agy Stop returns {} when continuationActive=true"

# 5. Test uninstall preserves non-gopher-ai plugin and removes gopher-ai-*
"$ROOT_DIR/scripts/install-agy.sh" --uninstall --config-dir "$TEST_CONFIG" >/dev/null

if [[ ! -d "$TEST_CONFIG/plugins/gopher-ai-go-workflow" && -f "$TEST_CONFIG/plugins/other-plugin/plugin.json" ]]; then
    pass "uninstall removes gopher-ai plugins and preserves other plugins"
else
    fail "uninstall did not cleanly remove only gopher-ai plugins"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
