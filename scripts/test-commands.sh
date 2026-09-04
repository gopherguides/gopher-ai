#!/bin/bash
# Verify all .md command files have valid YAML frontmatter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
case "$FIXTURE_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$FIXTURE_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac

ERRORS=0

echo "=== Command File Tests ==="

bash "$ROOT_DIR/scripts/test-review-plan.sh"
bash "$ROOT_DIR/scripts/test-codex-compatibility-lanes.sh"
python3 "$ROOT_DIR/scripts/test-github-actions-runtimes.py"
bash "$ROOT_DIR/scripts/test-codex-review-model.sh"
bash "$ROOT_DIR/scripts/test-ship-ollama-model.sh"
bash "$ROOT_DIR/scripts/test-review-deep-actions.sh"
bash "$ROOT_DIR/scripts/test-decision-gates.sh"
bash "$ROOT_DIR/scripts/test-github-rest.sh"
bash "$ROOT_DIR/scripts/test-gopher-ai-review-action.sh"
bash "$ROOT_DIR/scripts/test-tmux-start.sh"
bash "$ROOT_DIR/scripts/test-cancel-loop.sh"
bash "$ROOT_DIR/scripts/test-go-dev-codex-skills.sh"
bash "$ROOT_DIR/scripts/test-llm-tools-codex-skills.sh"
bash "$ROOT_DIR/scripts/test-tailwind-codex-skills.sh"

python3 "$ROOT_DIR/scripts/test-codex-skill-arguments.py" --static-only

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

  # Check frontmatter for a description field
  if ! awk 'NR > 1 && /^---$/ { exit } /^description:/ { found = 1 } END { exit found ? 0 : 1 }' "$file"; then
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

echo -n "tmux-start matches issue windows exactly... "
GOPHER_AI_TMUX_START_SOURCE_ONLY=true source "$ROOT_DIR/plugins/go-workflow/scripts/tmux-start.sh"
TMUX_MATCH_FAILURE=""
TMUX_CANONICAL="gopher-ai-issue-12-fix-window-match"
TMUX_LEGACY="gopher-ai-issue-12"

assert_tmux_match() {
  local description="$1"
  local expected="$2"
  local windows="$3"
  local actual

  actual=$(printf '%s\n' "$windows" | find_existing_window "$TMUX_CANONICAL" "$TMUX_LEGACY")
  if [ "$actual" != "$expected" ]; then
    TMUX_MATCH_FAILURE="$description: expected '$expected', got '$actual'"
  fi
}

assert_tmux_match "canonical match" "$TMUX_CANONICAL" "$TMUX_CANONICAL"
assert_tmux_match "numeric prefix collision" "" $'gopher-ai-issue-1-old\ngopher-ai-issue-120-old\ngopher-ai-issue-123-old'
assert_tmux_match "repository collision" "" "another-repo-issue-12-fix-window-match"
assert_tmux_match "no match" "" "unrelated-window"
assert_tmux_match "legacy match" "$TMUX_LEGACY" "$TMUX_LEGACY"
assert_tmux_match "canonical priority" "$TMUX_CANONICAL" $'gopher-ai-issue-12\ngopher-ai-issue-12-fix-window-match'

if [ -n "$TMUX_MATCH_FAILURE" ]; then
  echo "FAIL ($TMUX_MATCH_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "User-only workflows avoid blocked Skill-tool composition... "
TMUX_START_SCRIPT="$ROOT_DIR/plugins/go-workflow/scripts/tmux-start.sh"
COMPLETE_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
COMPLETE_ISSUE_LOOP="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/loop-state.md"
START_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/start-issue/SKILL.md"
E2E_FINISH="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/mode-finish.md"
E2E_SKILL_CONTRACT="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
E2E_LOOP_CONTRACT="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/loop-state.md"
ADDRESS_REVIEW_SKILL="$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md"
ADDRESS_REVIEW_LOOP="$ROOT_DIR/plugins/go-workflow/skills/address-review/loop-management.md"
BLOCKED_COMPOSITION=$(awk '/Invoke `[$](start-issue|e2e-verify|ship)([ `])/' "$COMPLETE_ISSUE_SKILL" "$E2E_FINISH")

file_contains() {
  local needle="$1"
  local file="$2"
  awk -v needle="$needle" 'index($0, needle) { found = 1 } END { exit found ? 0 : 1 }' "$file"
}

ADDRESS_REVIEW_BOT_REGISTRY="$ROOT_DIR/plugins/go-workflow/skills/address-review/bot-registry.md"
ADDRESS_REVIEW_DISCOVERY="$ROOT_DIR/plugins/go-workflow/skills/address-review/setup-and-discovery.md"
GO_WORKFLOW_README="$ROOT_DIR/plugins/go-workflow/README.md"
CODEX_CONNECTOR_REGISTRY_ROW='| `chatgpt-codex-connector[bot]` | Connector-authored `+1` reaction on the current-head `codex-pull-request-review-summary`, or a separate connector-authored clean-result comment with matching `Reviewed commit:` evidence; either requires no unresolved inline comments from the connector | Current-head summary has unresolved inline comments from the connector | `@codex review` |'

echo -n "Address-review registers current-head Codex connector re-review... "
if ! file_contains "$CODEX_CONNECTOR_REGISTRY_ROW" "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'PR_HEAD_SHA' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'repos/$REPO_SLUG/issues/comments/$COMMENT_ID/reactions' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains "Didn't find any major issues" "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'Reviewed commit:' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'CODEX_CLEAN_RESULT_BODY' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'contains("codex-pull-request-review-summary")) | not' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains '| select(.body | test("Didn[' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 't find any major issues"))' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'independently from the persistent summary' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'CODEX_REACTION_APPROVED' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'CODEX_CLEAN_RESULT_APPROVED' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains '[ "$CODEX_UNRESOLVED_THREADS" -eq 0 ]' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'ISSUE_COMMENT_AUTHORS' "$ADDRESS_REVIEW_DISCOVERY" ||
   ! file_contains 'chatgpt-codex-connector[bot]' "$ADDRESS_REVIEW_DISCOVERY" ||
   ! file_contains 'chatgpt-codex-connector' "$ADDRESS_REVIEW_DISCOVERY" ||
   ! file_contains 'ISSUE_COMMENT_REVIEWERS' "$ADDRESS_REVIEW_BOT_REGISTRY" ||
   ! file_contains 'only when discovered' "$GO_WORKFLOW_README" ||
   ! file_contains '`chatgpt-codex-connector[bot]`' "$GO_WORKFLOW_README" ||
   ! file_contains 'Manual re-request through GitHub Reviewers' "$GO_WORKFLOW_README"; then
  echo "FAIL (Codex connector detection, trigger, or signal contract missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

codex_connector_approved() {
  local summary_body="$1"
  local issue_comments="$2"
  local reactions="$3"
  local head_sha="$4"
  local unresolved_threads="$5"
  local clean_result_body summary_commit reviewed_commit reaction_approved clean_result_approved

  clean_result_body=$(jq -r '[
    .[]
    | select(.user.login == "chatgpt-codex-connector[bot]")
    | select((.body | contains("codex-pull-request-review-summary")) | not)
    | select(.body | test("Didn[\u0027’]t find any major issues"))
  ] | sort_by(.created_at) | last.body // ""' <<< "$issue_comments")
  summary_commit=$(sed -n 's/.*`\([0-9a-fA-F]\{7,40\}\)`.*/\1/p' <<< "$summary_body" | head -1)
  reviewed_commit=$(sed -n 's/.*Reviewed commit:\*\{0,2\}[[:space:]]*`\{0,1\}\([0-9a-fA-F]\{7,40\}\).*/\1/p' <<< "$clean_result_body" | head -1)
  reaction_approved=$(jq -r 'any(.[]; .content == "+1" and .user.login == "chatgpt-codex-connector[bot]")' <<< "$reactions")
  clean_result_approved=false
  if grep -Eq "Didn['’]t find any major issues" <<< "$clean_result_body"; then
    clean_result_approved=true
  fi

  [ "$unresolved_threads" -eq 0 ] && {
    { [ -n "$summary_commit" ] && [[ "$head_sha" == "$summary_commit"* ]] && [ "$reaction_approved" = true ]; } ||
      { [ -n "$reviewed_commit" ] && [[ "$head_sha" == "$reviewed_commit"* ]] && [ "$clean_result_approved" = true ]; }
  }
}

echo -n "Codex connector approval requires a clean current-head result... "
CODEX_TEST_HEAD="0123456789abcdef0123456789abcdef01234567"
CODEX_SUMMARY=$'<!-- codex-pull-request-review-summary -->\n| Code Review | Complete | `0123456` |'
CODEX_CLEAN_RESULT=$'Codex Review: Didn\'t find any major issues.\nReviewed commit: `0123456`'
CODEX_BOLD_CLEAN_RESULT=$'Codex Review: Didn\'t find any major issues.\n**Reviewed commit:** `0123456`'
CODEX_WRONG_HEAD_RESULT=$'Codex Review: Didn’t find any major issues.\n**Reviewed commit:** `abcdef0`'
CODEX_MISSING_COMMIT_RESULT=$'Codex Review: Didn’t find any major issues.'
CODEX_NON_CLEAN_RESULT=$'Codex Review: Did find any major issues.\nReviewed commit: `0123456`'
CODEX_COMBINED_SUMMARY=$'<!-- codex-pull-request-review-summary -->\nDidn’t find any major issues\nReviewed commit: `0123456`'
CODEX_CLEAN_COMMENTS=$(jq -nc --arg body "$CODEX_CLEAN_RESULT" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_BOLD_CLEAN_COMMENTS=$(jq -nc --arg body "$CODEX_BOLD_CLEAN_RESULT" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_WRONG_HEAD_COMMENTS=$(jq -nc --arg body "$CODEX_WRONG_HEAD_RESULT" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_MISSING_COMMIT_COMMENTS=$(jq -nc --arg body "$CODEX_MISSING_COMMIT_RESULT" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_NON_CLEAN_COMMENTS=$(jq -nc --arg body "$CODEX_NON_CLEAN_RESULT" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_COMBINED_SUMMARY_COMMENTS=$(jq -nc --arg body "$CODEX_COMBINED_SUMMARY" '[{user:{login:"chatgpt-codex-connector[bot]"},body:$body,created_at:"2026-09-01T00:00:01Z"}]')
CODEX_NO_COMMENTS='[]'
CODEX_NO_REACTIONS='[]'
CODEX_PLUS_ONE='[{"content":"+1","user":{"login":"chatgpt-codex-connector[bot]"}}]'
if ! codex_connector_approved "$CODEX_SUMMARY" "$CODEX_CLEAN_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0 ||
   ! codex_connector_approved "$CODEX_SUMMARY" "$CODEX_BOLD_CLEAN_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0 ||
   codex_connector_approved "$CODEX_SUMMARY" "$CODEX_WRONG_HEAD_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0 ||
   codex_connector_approved "$CODEX_SUMMARY" "$CODEX_MISSING_COMMIT_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0 ||
   codex_connector_approved "$CODEX_SUMMARY" "$CODEX_NON_CLEAN_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0 ||
   codex_connector_approved "$CODEX_SUMMARY" "$CODEX_CLEAN_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 1 ||
   ! codex_connector_approved "$CODEX_SUMMARY" "$CODEX_NO_COMMENTS" "$CODEX_PLUS_ONE" "$CODEX_TEST_HEAD" 0 ||
   codex_connector_approved "$CODEX_COMBINED_SUMMARY" "$CODEX_COMBINED_SUMMARY_COMMENTS" "$CODEX_NO_REACTIONS" "$CODEX_TEST_HEAD" 0; then
  echo "FAIL (separate clean-result, wrong-head, unresolved-thread, reaction, or combined-body path regressed)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Shared skill resources use the cross-platform plugin-root contract... "
GO_WORKFLOW_SKILLS="$ROOT_DIR/plugins/go-workflow/skills"
GO_WORKFLOW_SKILL_RESOURCES=(
  "$GO_WORKFLOW_SKILLS"
  "$ROOT_DIR/plugins/go-workflow/lib"
  "$ROOT_DIR/plugins/go-workflow/agents"
)
GOPHER_GUIDES_SKILLS="$ROOT_DIR/plugins/gopher-guides/skills"
RESOURCE_CONTRACT_FAILURE=""
RESOURCE_SKILLS=("$GO_WORKFLOW_SKILLS"/*/SKILL.md "$GOPHER_GUIDES_SKILLS"/*/SKILL.md)
for resource_skill in "${RESOURCE_SKILLS[@]}"; do
  if ! file_contains '## Plugin Resource Resolution' "$resource_skill" ||
     ! file_contains '`<PLUGIN_ROOT>` is notation' "$resource_skill" ||
     ! file_contains 'concrete absolute plugin root before every resource read or command' "$resource_skill" ||
     ! file_contains 'directory containing the absolute selected `SKILL.md` path, then ascend two directories' "$resource_skill" ||
     ! file_contains 'injected `${CLAUDE_PLUGIN_ROOT}`' "$resource_skill"; then
    RESOURCE_CONTRACT_FAILURE="${resource_skill#"$ROOT_DIR"/} lacks the complete binding contract"
    break
  fi
done

LEGACY_SKILL_RESOURCE_PATHS=$(rg -n --glob '*.md' '\$\{CLAUDE_PLUGIN_ROOT\}/' \
  "${GO_WORKFLOW_SKILL_RESOURCES[@]}" "$GOPHER_GUIDES_SKILLS" || true)
CODEX_RESOURCE_PROBE="$ROOT_DIR/scripts/probe-codex-skill-resources.sh"
if [ -n "$RESOURCE_CONTRACT_FAILURE" ]; then
  echo "FAIL ($RESOURCE_CONTRACT_FAILURE)"
  ERRORS=$((ERRORS + 1))
elif [ -n "$LEGACY_SKILL_RESOURCE_PATHS" ]; then
  echo "FAIL (Claude-only executable resource paths remain)"
  echo "$LEGACY_SKILL_RESOURCE_PATHS"
  ERRORS=$((ERRORS + 1))
elif [ ! -f "$ROOT_DIR/plugins/go-workflow/lib/driver-interaction.md" ] ||
     [ ! -x "$ROOT_DIR/plugins/go-workflow/scripts/setup-loop.sh" ] ||
     [ ! -x "$ROOT_DIR/plugins/gopher-guides/scripts/cache-api.sh" ] ||
     [ ! -x "$ROOT_DIR/plugins/gopher-guides/scripts/clear-cache.sh" ]; then
  echo "FAIL (representative bundled resources are missing)"
  ERRORS=$((ERRORS + 1))
elif [ ! -x "$CODEX_RESOURCE_PROBE" ]; then
  echo "FAIL (live Codex resource probe is missing or not executable)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'codex exec' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains '--sandbox read-only' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'env -u PLUGIN_ROOT -u PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'GO_WORKFLOW_PLUGIN_ROOT=' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'GOPHER_GUIDES_PLUGIN_ROOT=' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'GO_WEB_PLUGIN_ROOT=' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'references/convert-to-go-project.md' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'scripts/cache-api.sh' "$CODEX_RESOURCE_PROBE" ||
     ! file_contains 'Usage: cache-api.sh <endpoint> <json-data>' "$CODEX_RESOURCE_PROBE"; then
  echo "FAIL (live Codex resource probe lacks required safety or evidence checks)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

if [ -n "$BLOCKED_COMPOSITION" ]; then
  echo "FAIL"
  echo "$BLOCKED_COMPOSITION"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Read `<PLUGIN_ROOT>/skills/start-issue/SKILL.md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load start-issue directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Read `<PLUGIN_ROOT>/skills/e2e-verify/SKILL.md`' "$COMPLETE_ISSUE_SKILL"; then
  echo "FAIL (complete-issue does not load e2e-verify directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'skills/ship/SKILL.md' "$E2E_FINISH"; then
  echo "FAIL (e2e-verify does not load ship directly)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'dispatch_start_issue "$WINDOW_NAME" "$SURFACE" "$ISSUE_NUM"' "$TMUX_START_SCRIPT"; then
  echo "FAIL (tmux-start does not dispatch through the selected surface)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains '--surface "$SURFACE"' "$ROOT_DIR/plugins/go-workflow/skills/tmux-start/SKILL.md"; then
  echo "FAIL (tmux-start skill does not bind the active surface)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

composition_contract_section() {
  awk '
    /^## Embedded Workflow Contract$/ { active = 1; next }
    active && /^## / { exit }
    active { print }
  ' "$1"
}

validate_composition_contract() {
  local fixture_root="$1"
  local complete_skill="$fixture_root/plugins/go-workflow/skills/complete-issue/SKILL.md"
  local complete_loop="$fixture_root/plugins/go-workflow/skills/complete-issue/loop-state.md"
  local start_skill="$fixture_root/plugins/go-workflow/skills/start-issue/SKILL.md"
  local e2e_skill="$fixture_root/plugins/go-workflow/skills/e2e-verify/SKILL.md"
  local e2e_loop="$fixture_root/plugins/go-workflow/skills/e2e-verify/loop-state.md"
  local e2e_finish="$fixture_root/plugins/go-workflow/skills/e2e-verify/mode-finish.md"
  local address_skill="$fixture_root/plugins/go-workflow/skills/address-review/SKILL.md"
  local address_loop="$fixture_root/plugins/go-workflow/skills/address-review/loop-management.md"
  local embedded_section=""
  local embedded_file=""

  grep -Fq 'STATE_FILE=$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")' "$complete_loop" || return 1
  grep -Fq '"$STATE_FILE" '\''["COMPLETE","INCOMPLETE"]'\''' "$complete_loop" || return 1
  grep -Fq 'START_ISSUE_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "start_issue")' "$complete_skill" || return 1
  grep -Fq 'E2E_VERIFY_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "e2e_verify")' "$complete_skill" || return 1
  grep -Fq 'CALLER_LOOP_STATE_FILE="$STATE_FILE"' "$complete_skill" || return 1
  [ "$(grep -Fc 'CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"' "$complete_skill")" -ge 2 ] || return 1
  [ "$(grep -Fc 'WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"' "$complete_skill")" -ge 2 ] || return 1
  grep -Fq 'set_loop_terminal_result "$STATE_FILE" "incomplete"' "$complete_skill" || return 1
  grep -Fq 'ADDRESS_REVIEW_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "address_review")' "$e2e_skill" || return 1
  grep -Fq 'SHIP_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "ship")' "$e2e_finish" || return 1

  for embedded_file in "$start_skill" "$e2e_skill" "$address_skill"; do
    embedded_section=$(composition_contract_section "$embedded_file")
    [ -n "$embedded_section" ] || return 1
    grep -Fq 'CALLER_LOOP_STATE_FILE' <<< "$embedded_section" || return 1
    grep -Fq 'CALLER_WORKFLOW_STATE_PATH' <<< "$embedded_section" || return 1
    grep -Fq 'initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"' <<< "$embedded_section" || return 1
    grep -Fq 'set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH"' <<< "$embedded_section" || return 1
    if grep -Fq 'setup-loop.sh' <<< "$embedded_section"; then return 1; fi
    if grep -Fq '<done>' <<< "$embedded_section"; then return 1; fi
  done

  grep -Fq 'WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "start_issue")' "$start_skill" || return 1
  grep -Fq 'WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "e2e_verify")' "$e2e_skill" || return 1
  grep -Fq 'WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "address_review")' "$address_skill" || return 1
  grep -Fq 'CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"' "$e2e_skill" || return 1
  grep -Fq 'CALLER_WORKFLOW_STATE_PATH="$WORKFLOW_STATE_PATH"' "$e2e_finish" || return 1
  grep -Fq 'WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"' "$e2e_skill" || return 1
  grep -Fq 'WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"' "$e2e_finish" || return 1

  grep -Fq '"$STATE_FILE" '\''["COMPLETE","INCOMPLETE"]'\''' "$start_skill" || return 1
  grep -Fq '"$STATE_FILE" '\''["VERIFIED","E2E_FAIL","INCOMPLETE"]'\''' "$e2e_loop" || return 1
  grep -Fq '"$LOOP_STATE_FILE" '\''["COMPLETE","INCOMPLETE"]'\''' "$address_loop" || return 1
}

seed_composition_mutation() {
  local file="$1"
  local mutation="$2"
  local output="$file.mutated"

  awk -v mutation="$mutation" '
    { print }
    $0 == "## Embedded Workflow Contract" { print mutation }
  ' "$file" > "$output"
  mv "$output" "$file"
}

echo -n "Composed workflows keep one caller-owned loop and structured child results... "
COMPOSITION_FAILURE=""
if ! validate_composition_contract "$ROOT_DIR"; then
  COMPOSITION_FAILURE="composition contract is incomplete"
elif ! (
  source "$ROOT_DIR/plugins/go-workflow/lib/loop-state.sh"
  COMPOSITION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-composition-state.XXXXXX") || exit 1
  COMPOSITION_CLEANUP_ROOT=$(cd "$COMPOSITION_ROOT" && pwd -P) || exit 1
  trap 'rm -rf "$COMPOSITION_CLEANUP_ROOT"' EXIT
  cd "$COMPOSITION_CLEANUP_ROOT" || exit 1
  COMPOSITION_ROOT=$COMPOSITION_CLEANUP_ROOT
  [ "$(resolve_loop_owner_root)" = "$COMPOSITION_ROOT" ]
  mkdir -p "$COMPOSITION_ROOT/.local/state"
  STATE_FILE="$COMPOSITION_ROOT/.local/state/complete-issue-302.loop.local.json"
  printf '%s\n' '{"schema_version":2,"owner_workflow":"complete-issue","loop_name":"complete-issue-302","completion_promise":"COMPLETE","terminal_promises":["COMPLETE","INCOMPLETE"],"phase":"implementing","components":{}}' > "$STATE_FILE"
  WORKFLOW_STATE_PATH='[]'
  START_ISSUE_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "start_issue")
  E2E_VERIFY_STATE_PATH=$(child_workflow_path "$WORKFLOW_STATE_PATH" "e2e_verify")
  ADDRESS_REVIEW_STATE_PATH=$(child_workflow_path "$E2E_VERIFY_STATE_PATH" "address_review")
  SHIP_STATE_PATH=$(child_workflow_path "$E2E_VERIFY_STATE_PATH" "ship")
  initialize_workflow_state "$STATE_FILE" "$START_ISSUE_STATE_PATH"
  set_workflow_result "$STATE_FILE" "$START_ISSUE_STATE_PATH" "complete" "" "completed"
  initialize_workflow_state "$STATE_FILE" "$E2E_VERIFY_STATE_PATH"
  set_loop_phase "$STATE_FILE" "shipping" "$E2E_VERIFY_STATE_PATH"
  initialize_workflow_state "$STATE_FILE" "$ADDRESS_REVIEW_STATE_PATH"
  set_workflow_result "$STATE_FILE" "$ADDRESS_REVIEW_STATE_PATH" "complete" "" "completed"
  initialize_workflow_state "$STATE_FILE" "$SHIP_STATE_PATH"
  set_loop_phase "$STATE_FILE" "ci-watch" "$SHIP_STATE_PATH"
  set -- "$COMPOSITION_ROOT/.local/state/"*.loop.local.json
  [ "$#" -eq 1 ]
  jq -e '
    .completion_promise == "COMPLETE" and
    .terminal_promises == ["COMPLETE", "INCOMPLETE"] and
    .phase == "implementing" and
    .components.start_issue.result == "complete" and
    .components.e2e_verify.phase == "shipping" and
    .components.e2e_verify.components.address_review.result == "complete" and
    .components.e2e_verify.components.ship.phase == "ci-watch"
  ' "$STATE_FILE" >/dev/null
); then
  COMPOSITION_FAILURE="one-file component state fixture failed"
else
  COMPOSITION_MUTATION_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-composition-mutation.XXXXXX")
  mkdir -p "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue"
  mkdir -p "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/start-issue"
  mkdir -p "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify"
  mkdir -p "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/address-review"
  cp "$COMPLETE_ISSUE_SKILL" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md"
  cp "$COMPLETE_ISSUE_LOOP" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/loop-state.md"
  cp "$START_ISSUE_SKILL" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/start-issue/SKILL.md"
  cp "$E2E_SKILL_CONTRACT" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify/SKILL.md"
  cp "$E2E_LOOP_CONTRACT" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify/loop-state.md"
  cp "$E2E_FINISH" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify/mode-finish.md"
  cp "$ADDRESS_REVIEW_SKILL" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/address-review/SKILL.md"
  cp "$ADDRESS_REVIEW_LOOP" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/address-review/loop-management.md"

  seed_composition_mutation "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/start-issue/SKILL.md" '"<PLUGIN_ROOT>/scripts/setup-loop.sh" "nested" "COMPLETE"'
  if validate_composition_contract "$COMPOSITION_MUTATION_ROOT"; then
    COMPOSITION_FAILURE="validator accepted an embedded setup-loop mutation"
  fi
  cp "$START_ISSUE_SKILL" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/start-issue/SKILL.md"
  seed_composition_mutation "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify/SKILL.md" '<done>VERIFIED</done>'
  if validate_composition_contract "$COMPOSITION_MUTATION_ROOT"; then
    COMPOSITION_FAILURE="validator accepted an embedded terminal marker mutation"
  fi
  cp "$E2E_SKILL_CONTRACT" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/e2e-verify/SKILL.md"
  sed '/START_ISSUE_STATE_PATH=$(child_workflow_path/d' "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md" > "$COMPOSITION_MUTATION_ROOT/complete-without-start"
  mv "$COMPOSITION_MUTATION_ROOT/complete-without-start" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md"
  if validate_composition_contract "$COMPOSITION_MUTATION_ROOT"; then
    COMPOSITION_FAILURE="validator accepted a missing start-issue ownership contract"
  fi
  cp "$COMPLETE_ISSUE_SKILL" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md"
  sed '/WORKFLOW_STATE_PATH="$CALLER_WORKFLOW_STATE_PATH"/d' "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md" > "$COMPOSITION_MUTATION_ROOT/complete-without-restore"
  mv "$COMPOSITION_MUTATION_ROOT/complete-without-restore" "$COMPOSITION_MUTATION_ROOT/plugins/go-workflow/skills/complete-issue/SKILL.md"
  if validate_composition_contract "$COMPOSITION_MUTATION_ROOT"; then
    COMPOSITION_FAILURE="validator accepted a missing caller-path restoration"
  fi
  rm -rf "$COMPOSITION_MUTATION_ROOT"
fi

if [ -n "$COMPOSITION_FAILURE" ]; then
  echo "FAIL ($COMPOSITION_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Shared go-workflow skills bind native capabilities by intent... "
GO_WORKFLOW_SKILLS="$ROOT_DIR/plugins/go-workflow/skills"
GO_WORKFLOW_LIB="$ROOT_DIR/plugins/go-workflow/lib"
DRIVER_INTERACTION="$GO_WORKFLOW_LIB/driver-interaction.md"
shopt -s nullglob
GO_WORKFLOW_MARKDOWN=(
  "$GO_WORKFLOW_SKILLS"/*/*.md
  "$GO_WORKFLOW_LIB"/*.md
  "$GO_WORKFLOW_LIB"/*/*.md
)
PLATFORM_TOOL_NAMES=$(awk '
  /(^|[^[:alnum:]_])(AskUserQuestion|EnterPlanMode|Agent|Task)([^[:alnum:]_]|$)/ {
    print FILENAME ":" FNR ":" $0
  }
' "${GO_WORKFLOW_MARKDOWN[@]}")
SHARED_ALLOWED_TOOLS=$(awk '
  /^allowed-tools:/ { print FILENAME ":" FNR ":" $0 }
' "$GO_WORKFLOW_SKILLS"/*/SKILL.md)
MISSING_DRIVER_BINDING=""
for skill_file in "$GO_WORKFLOW_SKILLS"/*/SKILL.md; do
  if ! file_contains 'driver-interaction.md' "$skill_file"; then
    MISSING_DRIVER_BINDING="${skill_file#"$ROOT_DIR"/}"
    break
  fi
done

if [ -n "$PLATFORM_TOOL_NAMES" ]; then
  echo "FAIL (platform-specific tool names found)"
  echo "$PLATFORM_TOOL_NAMES"
  ERRORS=$((ERRORS + 1))
elif [ -n "$SHARED_ALLOWED_TOOLS" ]; then
  echo "FAIL (shared skill frontmatter still contains a platform tool allowlist)"
  echo "$SHARED_ALLOWED_TOOLS"
  ERRORS=$((ERRORS + 1))
elif [ -n "$MISSING_DRIVER_BINDING" ]; then
  echo "FAIL ($MISSING_DRIVER_BINDING does not load the driver interaction rules)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'native structured-input capability' "$DRIVER_INTERACTION" ||
     ! file_contains 'ask the concise question in the final' "$DRIVER_INTERACTION" ||
     ! file_contains 'pause_loop_for_driver' "$DRIVER_INTERACTION" ||
     ! file_contains 'resume_loop_after_driver' "$DRIVER_INTERACTION" ||
     ! file_contains 'Do not advance the phase' "$DRIVER_INTERACTION" ||
     ! file_contains 'emit a completion' "$DRIVER_INTERACTION"; then
  echo "FAIL (driver interaction rules do not preserve incomplete stop semantics)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Start-issue binds default orchestration to the active surface... "
START_ISSUE_ORCHESTRATION="$ROOT_DIR/plugins/go-workflow/lib/start-issue/orchestrated-workflow.md"
START_ISSUE_DISPATCH=$(awk '
  /^## Surface Dispatch Decision$/ { active = 1; next }
  active && /^## / { exit }
  active { print }
' "$START_ISSUE_SKILL")
START_ISSUE_PROMPT_CONTRACT=$(awk '
  /^## Reusable Prompt Contract$/ { active = 1; next }
  active && /^## / { exit }
  active { print }
' "$START_ISSUE_ORCHESTRATION")
START_ISSUE_CLAUDE_BINDING=$(awk '
  /^### Claude Code binding$/ { active = 1; next }
  active && /^### / { exit }
  active { print }
' "$START_ISSUE_ORCHESTRATION")
START_ISSUE_CODEX_BINDING=$(awk '
  /^### Codex binding$/ { active = 1; next }
  active && /^### / { exit }
  active { print }
' "$START_ISSUE_ORCHESTRATION")
START_ISSUE_FLAG_PARSER=$(awk '
  /^## Security Validation & Flag Parsing$/ { section = 1; next }
  section && /^```bash$/ { code = 1; next }
  code && /^```$/ { exit }
  code { print }
' "$START_ISSUE_SKILL")
START_ISSUE_DEFAULT_PARSE=$(SKILL_ARGS="328" bash -euo pipefail -c \
  "$START_ISSUE_FLAG_PARSER"$'\n''printf "PARSED:%s:%s\n" "$ISSUE_NUM" "$NO_AGENTS"')
START_ISSUE_MANUAL_PARSE=$(SKILL_ARGS="328 --no-agents" bash -euo pipefail -c \
  "$START_ISSUE_FLAG_PARSER"$'\n''printf "PARSED:%s:%s\n" "$ISSUE_NUM" "$NO_AGENTS"')
START_ISSUE_PARSER_LINE=$(awk '/^## Security Validation & Flag Parsing$/ { print NR; exit }' "$START_ISSUE_SKILL")
START_ISSUE_FLAG_STORE_LINE=$(awk '/^- `NO_AGENTS`:/{ print NR; exit }' "$START_ISSUE_SKILL")
START_ISSUE_DISPATCH_LINE=$(awk '/^## Surface Dispatch Decision$/ { print NR; exit }' "$START_ISSUE_SKILL")
START_ISSUE_SURFACE_FAILURE=""

record_start_issue_surface_failure() {
  if [ -z "$START_ISSUE_SURFACE_FAILURE" ]; then
    START_ISSUE_SURFACE_FAILURE="$1"
  else
    START_ISSUE_SURFACE_FAILURE="$START_ISSUE_SURFACE_FAILURE; $1"
  fi
}

case "$START_ISSUE_DEFAULT_PARSE" in
  *$'\nPARSED:328:false'|PARSED:328:false) ;;
  *) record_start_issue_surface_failure "default parser did not bind ISSUE_NUM=328 and NO_AGENTS=false" ;;
esac

case "$START_ISSUE_MANUAL_PARSE" in
  *$'\nPARSED:328:true'|PARSED:328:true) ;;
  *) record_start_issue_surface_failure "--no-agents parser did not bind ISSUE_NUM=328 and NO_AGENTS=true" ;;
esac

if [ -z "$START_ISSUE_PARSER_LINE" ] || [ -z "$START_ISSUE_FLAG_STORE_LINE" ] ||
   [ -z "$START_ISSUE_DISPATCH_LINE" ] ||
   [ "$START_ISSUE_DISPATCH_LINE" -le "$START_ISSUE_PARSER_LINE" ] ||
   [ "$START_ISSUE_DISPATCH_LINE" -le "$START_ISSUE_FLAG_STORE_LINE" ]; then
  record_start_issue_surface_failure "dispatch decision occurs before NO_AGENTS is parsed and stored"
fi

case "$START_ISSUE_DISPATCH" in
  *'explain why native orchestration is unavailable'*) ;;
  *) record_start_issue_surface_failure "fallback does not explain why native orchestration is unavailable" ;;
esac

for required in 'NO_AGENTS=true' 'manual-workflow.md' 'NO_AGENTS=false' 'Codex' 'native delegation capability' 'orchestrated-workflow.md'; do
  case "$START_ISSUE_DISPATCH" in
    *"$required"*) ;;
    *)
    START_ISSUE_SURFACE_FAILURE="dispatch decision is missing '$required'"
    break
    ;;
  esac
done

if [ -z "$START_ISSUE_SURFACE_FAILURE" ]; then
  for required in 'Explore' 'Implementer' 'Spec Review' 'Quality Review' 'subagent_type'; do
    case "$START_ISSUE_CLAUDE_BINDING" in
      *"$required"*) ;;
      *)
      START_ISSUE_SURFACE_FAILURE="Claude binding is missing '$required'"
      break
      ;;
    esac
  done
fi

if [ -z "$START_ISSUE_SURFACE_FAILURE" ]; then
  for required in 'Explore' 'Implementer' 'Spec Review' 'Quality Review' '`explorer`' '`worker`' '`default`' 'synchronously'; do
    case "$START_ISSUE_CODEX_BINDING" in
      *"$required"*) ;;
      *)
      START_ISSUE_SURFACE_FAILURE="Codex binding is missing '$required'"
      break
      ;;
    esac
  done
fi

if [ -z "$START_ISSUE_SURFACE_FAILURE" ] &&
   [[ "$START_ISSUE_CODEX_BINDING" =~ subagent_type|haiku|sonnet|CLAUDE_CODE_SUBAGENT_MODEL ]]; then
  START_ISSUE_SURFACE_FAILURE="Codex binding contains Claude-only dispatch or model controls"
fi

if [ -z "$START_ISSUE_SURFACE_FAILURE" ]; then
  for required in 'Markdown body' 'frontmatter' 'surface-neutral'; do
    case "$START_ISSUE_PROMPT_CONTRACT" in
      *"$required"*) ;;
      *)
      START_ISSUE_SURFACE_FAILURE="reusable prompt contract is missing '$required'"
      break
      ;;
    esac
  done
fi

for prompt_file in \
  "$ROOT_DIR/plugins/go-workflow/agents/explore-prompt.md" \
  "$ROOT_DIR/plugins/go-workflow/agents/implementer-prompt.md" \
  "$ROOT_DIR/plugins/go-workflow/agents/spec-review-prompt.md" \
  "$ROOT_DIR/plugins/go-workflow/agents/quality-review-prompt.md"; do
  PROMPT_MARKDOWN_BODY=$(awk '
    /^---$/ { separators += 1; next }
    separators >= 2 { print }
  ' "$prompt_file")
  if [[ "$PROMPT_MARKDOWN_BODY" =~ Grep|Glob|subagent_type|CLAUDE_CODE_SUBAGENT_MODEL|haiku|sonnet ]]; then
    record_start_issue_surface_failure "$(basename "$prompt_file") Markdown body contains surface-specific term '${BASH_REMATCH[0]}'"
  fi
done

if [ -n "$START_ISSUE_SURFACE_FAILURE" ]; then
  echo "FAIL ($START_ISSUE_SURFACE_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Address-review stages only fix-cycle files... "
ADDRESS_REVIEW_FIX_CYCLE="$ROOT_DIR/plugins/go-workflow/skills/address-review/fix-cycle.md"
if file_contains 'git add -A' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (broad staging can capture unrelated worktree changes)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'Stage only files modified during this fix cycle' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (owned-file staging policy missing)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'git -C "$WORKTREE_PATH" status --porcelain -- "$TARGET_FILE"' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (pre-existing target-file changes are not guarded)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'git -C "$WORKTREE_PATH" add -- "${OWNED_FILES[@]}"' "$ADDRESS_REVIEW_FIX_CYCLE"; then
  echo "FAIL (owned-file staging command missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "E2E preserves generated-path ownership across address-review... "
E2E_REBASE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/rebase-and-build.md"
E2E_SKILL="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
E2E_LOOP_STATE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/loop-state.md"
E2E_ADDRESSING=$(awk '
  /^## Step 3:/ { active = 1 }
  /^## Step 4:/ { exit }
  active { print }
' "$E2E_SKILL")
E2E_ADDRESS_REVIEW_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /follow [*][*]Steps 2-11 only[*][*]/ { print NR; found = 1 }')
E2E_EMPTY_INDEX_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /if ! git -C "[$]WORKTREE_PATH" diff --cached --quiet; then/ { print NR; found = 1 }')
E2E_GENERATOR_RERUN_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /make "[$]GEN_TARGET"/ { print NR; found = 1 }')
E2E_GENERATED_STAGE_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && index($0, "git -C \"$WORKTREE_PATH\" add -- \"${GEN_NEW_FILES[@]}\"") { print NR; found = 1 }')
E2E_GENERATED_COMMIT_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /git -C "[$]WORKTREE_PATH" commit -m "chore: refresh generated output"/ { print NR; found = 1 }')
E2E_GENERATED_PUSH_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '/git -C "[$]WORKTREE_PATH" commit -m "chore: refresh generated output"/ { commit_seen = 1 } commit_seen && !found && /git -C "[$]WORKTREE_PATH" push "[$]PR_HEAD_PUSH_TARGET"/ { print NR; found = 1 }')
E2E_POST_FIX_VERIFY_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /BUILD_RESULT=pass/ { print NR; found = 1 }')
E2E_FINAL_HEAD_LINE=$(printf '%s\n' "$E2E_ADDRESSING" | awk '!found && /FINAL_REVIEW_HEAD=[$][(]git -C "[$]WORKTREE_PATH" rev-parse HEAD[)]/ { print NR; found = 1 }')
E2E_BASELINE_PERSIST_LINE=$(awk '!found && index($0, "set_loop_field \"$STATE_FILE\" \"generation_target\"") { print NR; found = 1 }' "$E2E_REBASE")
E2E_INITIAL_GENERATOR_LINE=$(awk '!found && /make "[$]GEN_TARGET"/ { print NR; found = 1 }' "$E2E_REBASE")
E2E_OWNED_APPEND_LINE=$(awk '!found && index($0, "GEN_NEW_FILES+=(\"$GENERATED_FILE\")") { print NR; found = 1 }' "$E2E_REBASE")
E2E_OWNED_PERSIST_LINE=$(awk '!found && index($0, "set_loop_json_field \"$STATE_FILE\" \"generated_files\"") { print NR; found = 1 }' "$E2E_REBASE")

markdown_bash_after() {
  local file="$1"
  local heading="$2"

  awk -v heading="$heading" '
    index($0, heading) { found_heading = 1; next }
    found_heading && /^```bash$/ { in_block = 1; next }
    in_block && /^```$/ { exit }
    in_block { print }
  ' "$file"
}

E2E_INIT_CODE=$(markdown_bash_after "$E2E_REBASE" "### 2a. Code Generation")
E2E_DRIFT_CODE=$(markdown_bash_after "$E2E_REBASE" "Check for generated file drift:")
E2E_PERSIST_CODE=$(markdown_bash_after "$E2E_LOOP_STATE" "## Persist Build Result" | awk '/^TMP=/{exit} {print}')
E2E_RECOVER_CODE=$(markdown_bash_after "$E2E_LOOP_STATE" "## Re-entry Check" | awk '/^  E2E_STATE_JSON=/{active=1} active {print} /^  done </ {exit}')
E2E_TRANSACTION_RECOVERY_CODE=$(markdown_bash_after "$E2E_SKILL" "### Recover an Interrupted Generated-Output Transaction")
E2E_INDEX_CODE=$(markdown_bash_after "$E2E_SKILL" "### Require Empty Index After Review")
E2E_REFRESH_CODE=$(markdown_bash_after "$E2E_SKILL" "### Refresh Generated Output After Review")
E2E_STAGE_CODE=$(markdown_bash_after "$E2E_SKILL" "### Commit E2E-Owned Generated Output")
E2E_RUNTIME_FAILURE=""
if E2E_RUNTIME_OUTPUT=$(
  E2E_INIT_CODE="$E2E_INIT_CODE" \
  E2E_DRIFT_CODE="$E2E_DRIFT_CODE" \
  E2E_PERSIST_CODE="$E2E_PERSIST_CODE" \
  E2E_RECOVER_CODE="$E2E_RECOVER_CODE" \
  E2E_TRANSACTION_RECOVERY_CODE="$E2E_TRANSACTION_RECOVERY_CODE" \
  E2E_INDEX_CODE="$E2E_INDEX_CODE" \
  E2E_REFRESH_CODE="$E2E_REFRESH_CODE" \
  E2E_STAGE_CODE="$E2E_STAGE_CODE" \
  /bin/bash -eu -c '
    WORKTREE_PATH="$PWD"
    WORKFLOW_STATE_PATH="[]"
    GENERATED_PATH=$(printf "generated/é\noutput.go")
    BUILD_RESULT=pass
    BASE_BRANCH=main
    STATE_FILE=/dev/null
    set_loop_phase() { return 0; }
    set_loop_field() {
      [ "$1" = /dev/null ] && return 0
      local tmp_file="${1}.tmp"
      jq --arg field "$2" --arg value "$3" ".[\$field] = \$value" "$1" > "$tmp_file" && mv "$tmp_file" "$1"
    }
    set_loop_json_field() {
      [ "$1" = /dev/null ] && return 0
      local tmp_file="${1}.tmp"
      jq --arg field "$2" --argjson value "$3" ".[\$field] = \$value" "$1" > "$tmp_file" && mv "$tmp_file" "$1"
    }
    eval "$E2E_INIT_CODE"
    eval "$E2E_PERSIST_CODE"
    [ "$GENERATED_FILES_JSON" = "[]" ] || exit 1

    git() {
      if [ "${1:-}" = "-C" ]; then shift 2; fi
      case "$*" in
        "diff --name-only -z") return 0 ;;
        "ls-files --others --exclude-standard -z") printf "%s\0" "$GENERATED_PATH" ;;
        *) return 1 ;;
      esac
    }
    GEN_TARGET=generate
    GEN_SNAPSHOT_FILES=()
    WORKFLOW_REASON=""
    eval "$E2E_DRIFT_CODE" >/dev/null
    [ "${GEN_NEW_FILES[0]}" = "$GENERATED_PATH" ] || exit 1
    [ "${GEN_NEW_FILES[1]+set}" != "set" ] || exit 1

    eval "$E2E_PERSIST_CODE"
    [ "$(jq -r ".[0]" <<< "$GENERATED_FILES_JSON")" = "$GENERATED_PATH" ] || exit 1

    STATE_FILE=<(printf "{\"generation_target\":\"generate\",\"generation_snapshot\":[],\"generated_files\":[]}\n")
    eval "$E2E_RECOVER_CODE"
    STATE_FILE=/dev/null
    eval "$E2E_DRIFT_CODE" >/dev/null
    [ "${GEN_NEW_FILES[0]}" = "$GENERATED_PATH" ] || exit 1
    [ "${GEN_NEW_FILES[1]+set}" != "set" ] || exit 1

    unset GEN_TARGET
    STATE_FILE=<(printf "{\"generation_target\":\"generate\",\"generation_snapshot\":[],\"generated_files\":%s}\n" "$GENERATED_FILES_JSON")
    eval "$E2E_RECOVER_CODE"
    [ "$GEN_TARGET" = "generate" ] || exit 1
    [ "${GEN_NEW_FILES[0]}" = "$GENERATED_PATH" ] || exit 1

    git() {
      if [ "${1:-}" = "-C" ]; then shift 2; fi
      case "$*" in
        "diff --cached --quiet") return 0 ;;
        "diff --name-only -z") return 0 ;;
        "ls-files --others --exclude-standard -z") printf "%s\0" "$GENERATED_PATH" ;;
        *) return 1 ;;
      esac
    }
    eval "$E2E_INDEX_CODE"
    [ -z "$WORKFLOW_REASON" ] || exit 1

    make() { return 0; }
    eval "$E2E_REFRESH_CODE"
    [ "${GEN_NEW_FILES[0]}" = "$GENERATED_PATH" ] || exit 1
    [ "${GEN_NEW_FILES[1]+set}" != "set" ] || exit 1

    STATE_FILE=/dev/null
    STAGE_LOG=""
    LOCAL_HEAD=before
    PR_NUM=300
    COMMIT_FAIL=false
    PUSH_FAIL=false
    INDEX_STAGED=false
    CACHED_PATHS=("$GENERATED_PATH")
    INJECT_UNRELATED_AFTER_ADD=false
    github_pr() {
      printf "{\"head\":{\"sha\":\"%s\",\"ref\":\"issue-300\",\"repo\":{\"full_name\":\"gopherguides/gopher-ai\",\"clone_url\":\"https://github.com/gopherguides/gopher-ai.git\"}}}\n" "$LOCAL_HEAD"
    }
    git() {
      if [ "${1:-}" = "-C" ]; then shift 2; fi
      case "$1" in
        add)
          shift
          STAGE_LOG="add:$*"
          INDEX_STAGED=true
          if [ "$INJECT_UNRELATED_AFTER_ADD" = "true" ]; then
            CACHED_PATHS=("$GENERATED_PATH" "unrelated.txt")
          else
            CACHED_PATHS=("$GENERATED_PATH")
          fi
          ;;
        diff)
          if [ "$*" = "diff --cached --quiet" ]; then
            [ "$INDEX_STAGED" = "false" ]
          elif [ "$*" = "diff --cached --name-only -z" ]; then
            printf "%s\0" "${CACHED_PATHS[@]}"
          else
            return 1
          fi
          ;;
        commit)
          STAGE_LOG="$STAGE_LOG|commit:$*"
          if [ "$COMMIT_FAIL" = "true" ]; then return 1; fi
          LOCAL_HEAD=after
          INDEX_STAGED=false
          ;;
        push)
          STAGE_LOG="$STAGE_LOG|push:$*"
          if [ "$PUSH_FAIL" = "true" ]; then return 1; fi
          ;;
        remote)
          if [ "${2:-}" = "get-url" ]; then
            printf "%s\n" "https://github.com/gopherguides/gopher-ai.git"
          else
            printf "%s\n" origin
          fi
          ;;
        rev-parse) printf "%s\n" "$LOCAL_HEAD" ;;
        restore) INDEX_STAGED=false ;;
        *) return 1 ;;
      esac
    }
    eval "$E2E_STAGE_CODE"
    [ "$STAGE_LOG" = "add:-- $GENERATED_PATH|commit:commit -m chore: refresh generated output|push:push origin HEAD:refs/heads/issue-300" ] || exit 1
    [ "$PR_HEAD_SHA" = "after" ] || exit 1

    WORKFLOW_REASON=""
    STAGE_LOG=""
    LOCAL_HEAD=before
    INDEX_STAGED=false
    COMMIT_FAIL=true
    eval "$E2E_STAGE_CODE"
    [ "$WORKFLOW_REASON" = "generated-commit-failed" ] || exit 1
    [ "$STAGE_LOG" = "add:-- $GENERATED_PATH|commit:commit -m chore: refresh generated output" ] || exit 1
    [ "$INDEX_STAGED" = "false" ] || exit 1

    WORKFLOW_REASON=""
    STAGE_LOG=""
    LOCAL_HEAD=before
    INDEX_STAGED=false
    COMMIT_FAIL=false
    PUSH_FAIL=true
    eval "$E2E_STAGE_CODE"
    [ "$WORKFLOW_REASON" = "generated-push-failed" ] || exit 1
    [ "$STAGE_LOG" = "add:-- $GENERATED_PATH|commit:commit -m chore: refresh generated output|push:push origin HEAD:refs/heads/issue-300" ] || exit 1

    WORKFLOW_REASON=""
    STAGE_LOG=""
    LOCAL_HEAD=before
    INDEX_STAGED=true
    COMMIT_FAIL=false
    PUSH_FAIL=false
    eval "$E2E_STAGE_CODE"
    [ "$WORKFLOW_REASON" = "generator-staged-changes" ] || exit 1
    [ -z "$STAGE_LOG" ] || exit 1

    WORKFLOW_REASON=""
    STAGE_LOG=""
    GEN_NEW_FILES=()
    eval "$E2E_STAGE_CODE"
    [ "$WORKFLOW_REASON" = "generator-staged-changes" ] || exit 1
    [ -z "$STAGE_LOG" ] || exit 1

    WORKFLOW_REASON=""
    STAGE_LOG=""
    GEN_NEW_FILES=("$GENERATED_PATH")
    LOCAL_HEAD=before
    INDEX_STAGED=false
    INJECT_UNRELATED_AFTER_ADD=true
    eval "$E2E_STAGE_CODE"
    [ "$WORKFLOW_REASON" = "generated-index-mismatch" ] || exit 1
    [ "$STAGE_LOG" = "add:-- $GENERATED_PATH" ] || exit 1

    STATE_FILE=$(mktemp /tmp/e2e-generated-transaction-XXXXXX)
    trap '\''rm -f "$STATE_FILE"'\'' EXIT
    GEN_NEW_FILES=("$GENERATED_PATH")
    GENERATED_COMMIT_STATUS=committing
    GENERATED_COMMIT_PARENT=before
    GENERATED_COMMIT_SHA=""
    LOCAL_HEAD=before
    PUBLISHED_HEAD=before
    INDEX_STAGED=true
    CACHED_PATHS=("$GENERATED_PATH")
    WORKFLOW_REASON=""
    TRANSACTION_LOG=""
    printf "{\"generated_commit_status\":\"committing\",\"generated_commit_parent\":\"before\",\"generated_commit_sha\":\"\"}\n" > "$STATE_FILE"
    github_pr() {
      printf "{\"head\":{\"sha\":\"%s\",\"ref\":\"issue-300\",\"repo\":{\"full_name\":\"gopherguides/gopher-ai\",\"clone_url\":\"https://github.com/gopherguides/gopher-ai.git\"}}}\n" "$PUBLISHED_HEAD"
    }
    git() {
      if [ "${1:-}" = "-C" ]; then shift 2; fi
      case "$1" in
        diff)
          if [ "$*" = "diff --cached --name-only -z" ]; then printf "%s\0" "${CACHED_PATHS[@]}"; else return 1; fi
          ;;
        diff-tree) printf "%s\0" "$GENERATED_PATH" ;;
        restore) INDEX_STAGED=false; TRANSACTION_LOG="$TRANSACTION_LOG|restore" ;;
        rev-parse)
          if [ "${2:-}" = "HEAD" ]; then printf "%s\n" "$LOCAL_HEAD"; else printf "%s\n" before; fi
          ;;
        remote)
          if [ "${2:-}" = "get-url" ]; then printf "%s\n" "https://github.com/gopherguides/gopher-ai.git"; else printf "%s\n" origin; fi
          ;;
        push) PUBLISHED_HEAD=after; TRANSACTION_LOG="$TRANSACTION_LOG|push" ;;
        *) return 1 ;;
      esac
    }
    eval "$E2E_TRANSACTION_RECOVERY_CODE"
    [ -z "$WORKFLOW_REASON" ] || exit 1
    [ "$INDEX_STAGED" = "false" ] || exit 1
    [ -z "$GENERATED_COMMIT_STATUS" ] || exit 1
    [ "$(jq -r ".generated_commit_status" "$STATE_FILE")" = "" ] || exit 1

    GENERATED_COMMIT_STATUS=committing
    GENERATED_COMMIT_PARENT=before
    GENERATED_COMMIT_SHA=""
    LOCAL_HEAD=after
    PUBLISHED_HEAD=before
    INDEX_STAGED=false
    WORKFLOW_REASON=""
    TRANSACTION_LOG=""
    printf "{\"generated_commit_status\":\"committing\",\"generated_commit_parent\":\"before\",\"generated_commit_sha\":\"\"}\n" > "$STATE_FILE"
    eval "$E2E_TRANSACTION_RECOVERY_CODE"
    [ -z "$WORKFLOW_REASON" ] || exit 1
    [ "$GENERATED_PUSH_RECOVERED" = "true" ] || exit 1
    [ "$PUBLISHED_HEAD" = "after" ] || exit 1
    [ "$TRANSACTION_LOG" = "|push" ] || exit 1
    [ "$(jq -r ".generated_commit_status" "$STATE_FILE")" = "" ] || exit 1
  ' 2>&1
); then
  E2E_RUNTIME_FAILURE=""
else
  E2E_RUNTIME_FAILURE="$E2E_RUNTIME_OUTPUT"
fi

if file_contains 'xargs git add' "$E2E_REBASE" ||
   file_contains 'git add -- "${GEN_NEW_FILES[@]}"' "$E2E_REBASE"; then
  echo "FAIL (generated paths are staged before embedded address-review)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'GEN_NEW_FILES+=("$GENERATED_FILE")' "$E2E_REBASE" ||
     ! file_contains 'Keep the generated paths unstaged' "$E2E_REBASE"; then
  echo "FAIL (generated drift is not retained as an unstaged owned-path array)"
  ERRORS=$((ERRORS + 1))
elif file_contains 'GEN_NEW_FILES=("${GEN_NEW_FILES[@]}")' "$E2E_REBASE" ||
     ! file_contains 'if ! declare -p GEN_NEW_FILES >/dev/null 2>&1; then' "$E2E_REBASE" ||
     ! file_contains 'GEN_NEW_FILES=()' "$E2E_REBASE" ||
     ! file_contains '${GEN_NEW_FILES[0]+set}' "$E2E_REBASE" ||
     ! file_contains '${GEN_NEW_FILES[0]+set}' "$E2E_LOOP_STATE" ||
     ! file_contains '${GEN_NEW_FILES[0]+set}' "$E2E_SKILL"; then
  echo "FAIL (fresh E2E runs do not initialize generated paths safely under nounset)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'set_loop_json_field "$STATE_FILE" "generated_files" "$GENERATED_FILES_JSON" "$WORKFLOW_STATE_PATH"' "$E2E_LOOP_STATE" ||
     ! file_contains 'set_loop_field "$STATE_FILE" "generation_target" "${GEN_TARGET:-}" "$WORKFLOW_STATE_PATH"' "$E2E_LOOP_STATE" ||
     ! file_contains "GEN_TARGET=\$(jq -r '.generation_target // empty'" "$E2E_LOOP_STATE" ||
     ! file_contains 'set_loop_json_field "$STATE_FILE" "generation_snapshot" "$GENERATION_SNAPSHOT_JSON" "$WORKFLOW_STATE_PATH"' "$E2E_LOOP_STATE" ||
     ! file_contains 'generated_commit_status generated_commit_parent generated_commit_sha' "$E2E_LOOP_STATE" ||
     ! file_contains "GENERATED_COMMIT_STATUS=\$(jq -r '.generated_commit_status // empty'" "$E2E_LOOP_STATE" ||
     ! file_contains '[ "${PHASE:-}" = "incomplete" ]' "$E2E_LOOP_STATE" ||
     ! file_contains 'set_loop_phase "$STATE_FILE" "building" "$WORKFLOW_STATE_PATH"' "$E2E_LOOP_STATE" ||
     ! file_contains 'jq -cn '\''$ARGS.positional'\'' --args "${GEN_NEW_FILES[@]}"' "$E2E_LOOP_STATE" ||
     ! file_contains "while IFS= read -r -d '' GENERATED_FILE" "$E2E_LOOP_STATE" ||
     ! file_contains '.generated_files[]?' "$E2E_LOOP_STATE"; then
  echo "FAIL (generated-path JSON persistence or re-entry recovery missing)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'if [ -z "${GEN_TARGET:-}" ]; then' "$E2E_REBASE" ||
     ! file_contains 'set_loop_field "$STATE_FILE" "generation_target" "$GEN_TARGET" "$WORKFLOW_STATE_PATH"' "$E2E_REBASE" ||
     ! file_contains 'set_loop_json_field "$STATE_FILE" "generation_snapshot" "$GENERATION_SNAPSHOT_JSON" "$WORKFLOW_STATE_PATH"' "$E2E_REBASE" ||
     ! file_contains 'set_loop_json_field "$STATE_FILE" "generated_files" "$GENERATED_FILES_JSON" "$WORKFLOW_STATE_PATH"' "$E2E_REBASE" ||
     [ -z "$E2E_BASELINE_PERSIST_LINE" ] || [ -z "$E2E_INITIAL_GENERATOR_LINE" ] ||
     [ -z "$E2E_OWNED_APPEND_LINE" ] || [ -z "$E2E_OWNED_PERSIST_LINE" ] ||
     [ "$E2E_BASELINE_PERSIST_LINE" -ge "$E2E_INITIAL_GENERATOR_LINE" ] ||
     [ "$E2E_OWNED_APPEND_LINE" -ge "$E2E_OWNED_PERSIST_LINE" ]; then
  echo "FAIL (generation ownership is not persisted before or immediately after generation)"
  ERRORS=$((ERRORS + 1))
elif [ -z "$E2E_ADDRESS_REVIEW_LINE" ] || [ -z "$E2E_EMPTY_INDEX_LINE" ] ||
     [ -z "$E2E_GENERATOR_RERUN_LINE" ] ||
     [ -z "$E2E_GENERATED_STAGE_LINE" ] ||
     [ -z "$E2E_GENERATED_COMMIT_LINE" ] || [ -z "$E2E_GENERATED_PUSH_LINE" ] ||
     [ -z "$E2E_POST_FIX_VERIFY_LINE" ] || [ -z "$E2E_FINAL_HEAD_LINE" ] ||
     [ "$E2E_ADDRESS_REVIEW_LINE" -ge "$E2E_EMPTY_INDEX_LINE" ] ||
     [ "$E2E_EMPTY_INDEX_LINE" -ge "$E2E_GENERATOR_RERUN_LINE" ] ||
     [ "$E2E_GENERATOR_RERUN_LINE" -ge "$E2E_GENERATED_STAGE_LINE" ] ||
     [ "$E2E_EMPTY_INDEX_LINE" -ge "$E2E_GENERATED_STAGE_LINE" ] ||
     [ "$E2E_GENERATED_STAGE_LINE" -ge "$E2E_GENERATED_COMMIT_LINE" ] ||
     [ "$E2E_GENERATED_COMMIT_LINE" -ge "$E2E_GENERATED_PUSH_LINE" ] ||
     [ "$E2E_GENERATED_PUSH_LINE" -ge "$E2E_POST_FIX_VERIFY_LINE" ] ||
     [ "$E2E_POST_FIX_VERIFY_LINE" -ge "$E2E_FINAL_HEAD_LINE" ] ||
     ! file_contains 'WORKFLOW_REASON=generated-commit-failed' "$E2E_SKILL" ||
     ! file_contains 'WORKFLOW_REASON=generated-push-failed' "$E2E_SKILL" ||
     ! file_contains 'WORKFLOW_REASON=generator-staged-changes' "$E2E_SKILL" ||
     ! file_contains 'WORKFLOW_REASON=generated-index-mismatch' "$E2E_SKILL" ||
     ! file_contains 'GENERATED_COMMIT_STATUS=push-pending' "$E2E_SKILL" ||
     ! file_contains 'GENERATED_PUSH_RECOVERED=true' "$E2E_SKILL" ||
     ! file_contains 'PUBLISHED_FINAL_REVIEW_HEAD' "$E2E_SKILL" ||
     ! file_contains '[ "$PUBLISHED_FINAL_REVIEW_HEAD" != "$FINAL_REVIEW_HEAD" ]' "$E2E_SKILL" ||
     ! file_contains 'EXPECTED_REVIEW_HEAD="$FINAL_REVIEW_HEAD"' "$E2E_SKILL" ||
     ! file_contains 'REVIEW_HEAD_EXPECTATION="${EXPECTED_REVIEW_HEAD:-$(git -C "$WORKTREE_PATH" rev-parse HEAD)}"' "$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md" ||
     ! file_contains '[ "$PR_HEAD_SHA" != "$REVIEW_HEAD_EXPECTATION" ]' "$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md" ||
     ! file_contains 'repeat **Step 11' "$E2E_SKILL"; then
  echo "FAIL (fix modes do not refresh, commit, and verify the final generated-output head in order)"
  ERRORS=$((ERRORS + 1))
elif [ -n "$E2E_RUNTIME_FAILURE" ]; then
  echo "FAIL (generated-path runtime contract failed: $E2E_RUNTIME_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Go-workflow stages only phase-owned files... "
COMPLETE_ISSUE_PHASES="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/phases.md"
COMPLETE_ISSUE_SKILL_INDEX_GUARDS=$(awk \
  '/^[[:space:]]*if ! git -C "[$]WORKTREE_PATH" diff --cached --quiet; then$/ { count++ } END { print count + 0 }' \
  "$COMPLETE_ISSUE_SKILL")
COMPLETE_ISSUE_PHASE_INDEX_GUARDS=$(awk \
  '/^[[:space:]]*if ! git -C "[$]WORKTREE_PATH" diff --cached --quiet; then$/ { count++ } END { print count + 0 }' \
  "$COMPLETE_ISSUE_PHASES")
GO_WORKFLOW_AUDIT_FILES=()
while IFS= read -r workflow_file; do
  GO_WORKFLOW_AUDIT_FILES+=("$workflow_file")
done < <(find "$GO_WORKFLOW_SKILLS" "$GO_WORKFLOW_LIB" -type f -print)
LIVE_BROAD_STAGING=$(grep -nE '^[[:space:]]*git add -A([[:space:]]|$)' \
  "${GO_WORKFLOW_AUDIT_FILES[@]}" || true)
if [ -n "$LIVE_BROAD_STAGING" ]; then
  echo "FAIL (live broad staging commands found)"
  echo "$LIVE_BROAD_STAGING"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'git -C "$WORKTREE_PATH" add -- "${REVIEW_FILES[@]}"' "$COMPLETE_ISSUE_SKILL" ||
     ! file_contains 'git -C "$WORKTREE_PATH" add -- "${REVIEW_FILES[@]}"' "$COMPLETE_ISSUE_PHASES"; then
  echo "FAIL (complete-issue review-owned staging command missing)"
  ERRORS=$((ERRORS + 1))
elif [ "$COMPLETE_ISSUE_SKILL_INDEX_GUARDS" -ne 2 ] ||
     [ "$COMPLETE_ISSUE_PHASE_INDEX_GUARDS" -ne 2 ]; then
  echo "FAIL (complete-issue staged-diff commit guard missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Address-review records incomplete bot approval outcomes... "
ADDRESS_REVIEW_WATCH_LOOP="$ROOT_DIR/plugins/go-workflow/skills/address-review/watch-loop.md"
if file_contains 'If "exit" → output `<done>COMPLETE</done>`' "$ADDRESS_REVIEW_WATCH_LOOP"; then
  echo "FAIL (timeout exit is mislabeled complete)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'approval_result' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'approval_reason' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'bot-approval-timeout' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'bot-approval-exhausted' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'set_loop_field "$STATE_FILE" "approval_result" "incomplete" "$WORKFLOW_STATE_PATH"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains 'set_loop_terminal_result "$STATE_FILE" "incomplete" "$APPROVAL_REASON" "approval-incomplete" "INCOMPLETE"' "$ADDRESS_REVIEW_WATCH_LOOP" ||
     ! file_contains '<done>INCOMPLETE</done>' "$ADDRESS_REVIEW_WATCH_LOOP"; then
  echo "FAIL (durable incomplete approval outcome contract missing)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Issue-to-PR workflows persist absolute repository and worktree paths... "
START_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/start-issue/SKILL.md"
START_ISSUE_WORKTREE_CREATE="$ROOT_DIR/plugins/go-workflow/lib/start-issue/worktree-create.md"
COMPLETE_ISSUE_LOOP_STATE="$ROOT_DIR/plugins/go-workflow/skills/complete-issue/loop-state.md"
E2E_LOOP_STATE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/loop-state.md"
SHIP_SKILL="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
ADDRESS_REVIEW_LOOP_STATE="$ROOT_DIR/plugins/go-workflow/skills/address-review/loop-management.md"
PATH_CONTRACT_FAILURE=""

setup_loop_uses_state_path() {
  local file="$1"
  local state_expression="$2"

  awk -v state_expression="$state_expression" '
    /scripts\/setup-loop[.]sh/ { active = 1; remaining = 4 }
    active && index($0, state_expression) { found = 1 }
    active { remaining--; if (remaining == 0) active = 0 }
    END { exit found ? 0 : 1 }
  ' "$file"
}

if ! file_contains 'ORIGINAL_REPO_ROOT=' "$START_ISSUE_SKILL" ||
   ! file_contains 'STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/start-issue-$ISSUE_NUM.loop.local.json"' "$START_ISSUE_SKILL" ||
   ! file_contains '"$STATE_FILE"' "$START_ISSUE_SKILL" ||
   ! file_contains 'set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT"' "$START_ISSUE_SKILL" ||
   ! file_contains 'set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH"' "$START_ISSUE_SKILL"; then
  PATH_CONTRACT_FAILURE="start-issue does not bootstrap and persist absolute path outputs"
elif ! file_contains '.worktree_path = $worktree_path' "$START_ISSUE_WORKTREE_CREATE"; then
  PATH_CONTRACT_FAILURE="worktree creation does not persist its absolute output"
elif file_contains 'WORKTREE_PATH=$(pwd)' "$COMPLETE_ISSUE_SKILL" ||
     file_contains 'STATE_FILE="$(pwd)' "$COMPLETE_ISSUE_SKILL"; then
  PATH_CONTRACT_FAILURE="complete-issue still rediscovers paths from pwd"
elif ! file_contains 'WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '\''[]'\'')' "$COMPLETE_ISSUE_SKILL" ||
     ! file_contains 'WORKFLOW_REASON=start-issue-worktree-path-invalid' "$COMPLETE_ISSUE_SKILL" ||
     ! file_contains 'set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"' "$COMPLETE_ISSUE_SKILL"; then
  PATH_CONTRACT_FAILURE="complete-issue does not consume and validate the persisted start-issue output"
elif ! file_contains 'STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/complete-issue-${ISSUE_NUM}.loop.local.json"' "$COMPLETE_ISSUE_LOOP_STATE" ||
     ! file_contains '"$STATE_FILE"' "$COMPLETE_ISSUE_LOOP_STATE" ||
     ! file_contains 'WORKFLOW_REASON=start-issue-worktree-path-invalid' "$COMPLETE_ISSUE_LOOP_STATE" ||
     ! file_contains 'REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain' "$COMPLETE_ISSUE_LOOP_STATE"; then
  PATH_CONTRACT_FAILURE="complete-issue loop bootstrap is not absolutely anchored"
elif ! file_contains 'STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/e2e-verify-${PR_NUM}.loop.local.json"' "$E2E_SKILL_CONTRACT" ||
     ! file_contains '"$STATE_FILE"' "$E2E_LOOP_STATE"; then
  PATH_CONTRACT_FAILURE="e2e-verify loop bootstrap is not absolutely anchored"
elif ! file_contains 'CANONICAL_STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/ship.loop.local.json"' "$SHIP_SKILL" ||
     ! file_contains '"$STATE_FILE"' "$SHIP_SKILL"; then
  PATH_CONTRACT_FAILURE="ship loop bootstrap is not absolutely anchored"
elif ! file_contains 'LOOP_STATE_FILE="${STATE_FILE:-$ORIGINAL_REPO_ROOT/.local/state/${SAFE_LOOP_NAME}.loop.local.json}"' "$ADDRESS_REVIEW_LOOP_STATE" ||
     ! file_contains '"$LOOP_STATE_FILE"' "$ADDRESS_REVIEW_LOOP_STATE"; then
  PATH_CONTRACT_FAILURE="address-review loop bootstrap is not absolutely anchored"
elif ! setup_loop_uses_state_path "$START_ISSUE_SKILL" '"$STATE_FILE"' ||
     ! setup_loop_uses_state_path "$COMPLETE_ISSUE_LOOP_STATE" '"$STATE_FILE"' ||
     ! setup_loop_uses_state_path "$E2E_LOOP_STATE" '"$STATE_FILE"' ||
     ! setup_loop_uses_state_path "$SHIP_SKILL" '"$STATE_FILE"' ||
     ! setup_loop_uses_state_path "$ADDRESS_REVIEW_LOOP_STATE" '"$LOOP_STATE_FILE"'; then
  PATH_CONTRACT_FAILURE="a setup-loop bootstrap does not pass its absolute state path as argument six"
fi

if [ -n "$PATH_CONTRACT_FAILURE" ]; then
  echo "FAIL ($PATH_CONTRACT_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Post-worktree workflow commands are explicitly scoped... "
POST_WORKTREE_FILES=(
  "$START_ISSUE_SKILL"
  "$ROOT_DIR/plugins/go-workflow/lib/start-issue/orchestrated-workflow.md"
  "$ROOT_DIR/plugins/go-workflow/lib/start-issue/manual-workflow.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/phases.md"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/rebase-and-build.md"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/e2e-test-execution.md"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/pr-results-comment.md"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/mode-finish.md"
  "$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/bot-watch.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/ci-watch.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"
  "$ROOT_DIR/plugins/go-workflow/lib/ship/push-and-pr.md"
  "$ROOT_DIR"/plugins/go-workflow/lib/coverage/*.md
  "$ROOT_DIR"/plugins/go-workflow/skills/address-review/*.md
)
UNQUALIFIED_WORKTREE_COMMANDS=$(awk '
  function scoped(line) {
    return line ~ /git -C "[$]WORKTREE_PATH"/ ||
      line ~ /git -C "[$](ORIGINAL_REPO_ROOT|CURRENT_CHECKOUT_ROOT|RESOLVED_ORIGINAL_REPO_ROOT)"/ ||
      line ~ /go -C "[$]WORKTREE_PATH"/ ||
      line ~ /gh .*--repo "[$]REPO_SLUG"/ ||
      line ~ /gh api .*repos\/[$]REPO_SLUG/ ||
      line ~ /\(cd "[$]WORKTREE_PATH" &&/ ||
      line ~ /\(cd "[$]ORIGINAL_REPO_ROOT" &&/ ||
      line ~ /rm .*"[$]WORKTREE_PATH\// ||
      line ~ /rm -f ("\/tmp\/|"[$](PROMPT_FILE|SCHEMA_FILE))/ ||
      line ~ /command -v (go|git|gh|golangci-lint|govulncheck|cargo-llvm-cov|cargo-tarpaulin|pytest|coverage)/ ||
      line ~ /^[[:space:]]*CURRENT_CHECKOUT_ROOT=[$]\(git rev-parse --show-toplevel\)$/
  }
  FNR == 1 {
    shell = 0
    post_transition = FILENAME ~ /skills\/start-issue\/SKILL[.]md$/ ? 0 : 1
  }
  FILENAME ~ /skills\/start-issue\/SKILL[.]md$/ && /^## MANDATORY: All Work Happens in the Worktree/ { post_transition = 1 }
  post_transition && /^[[:space:]]*```bash[[:space:]]*$/ { shell = 1; next }
  shell && /^[[:space:]]*```[[:space:]]*$/ { shell = 0; next }
  shell && ($0 ~ /(^[[:space:]]*|[;&|!(][[:space:]]*)(git|go|gh|golangci-lint|govulncheck|make|cargo|npx|npm|pytest|coverage|rm|codex|gemini|ollama)([[:space:]]|$)/ ||
    $0 ~ /[$](DEV_SERVER_CMD|CODEX_CMD)/ ||
    $0 ~ /(select-ollama-model|cleanup-loop)[.]sh/) && !scoped($0) {
    print FILENAME ":" FNR ":" $0
  }
' "${POST_WORKTREE_FILES[@]}")

if [ -n "$UNQUALIFIED_WORKTREE_COMMANDS" ]; then
  echo "FAIL (live commands depend on ambient CWD)"
  echo "$UNQUALIFIED_WORKTREE_COMMANDS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Inline post-worktree commands are explicitly scoped... "
UNQUALIFIED_INLINE_COMMANDS=$(awk '
  function scoped(line) {
    return line ~ /git -C "[$]WORKTREE_PATH"/ ||
      line ~ /git -C "[$](ORIGINAL_REPO_ROOT|CURRENT_CHECKOUT_ROOT|RESOLVED_ORIGINAL_REPO_ROOT)"/ ||
      line ~ /go -C "[$]WORKTREE_PATH"/ ||
      line ~ /gh .*--repo "[$]REPO_SLUG"/ ||
      line ~ /gh api .*repos\/[$]REPO_SLUG/ ||
      line ~ /\(cd "[$]WORKTREE_PATH" &&/
  }
  FNR == 1 {
    shell = 0
    post_transition = FILENAME ~ /skills\/start-issue\/SKILL[.]md$/ ? 0 : 1
  }
  FILENAME ~ /skills\/start-issue\/SKILL[.]md$/ && /^## MANDATORY: All Work Happens in the Worktree/ { post_transition = 1 }
  /^[[:space:]]*```/ { shell = !shell; next }
  post_transition && !shell && $0 ~ /`(git|go|gh|golangci-lint|govulncheck|make|cargo|npx|npm|pytest|coverage)([[:space:]]|`)/ &&
    !scoped($0) &&
    $0 !~ /(store the raw executable|→|Fallback for Go|never `|do NOT use `|MUST NOT be passed|Avoid looping|instead of `|^\|)/ {
    print FILENAME ":" FNR ":" $0
  }
' "${POST_WORKTREE_FILES[@]}")

if [ -n "$UNQUALIFIED_INLINE_COMMANDS" ]; then
  echo "FAIL (inline commands depend on ambient CWD)"
  echo "$UNQUALIFIED_INLINE_COMMANDS"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Dynamic workflow commands preserve worktree scope... "
E2E_TEST_EXECUTION="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/e2e-test-execution.md"
SHIP_LOCAL_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
if ! file_contains 'store the raw executable' "$E2E_TEST_EXECUTION" ||
   file_contains 'command: `(cd "$WORKTREE_PATH" && make <target>)`' "$E2E_TEST_EXECUTION" ||
   ! file_contains '"$WORKTREE_PATH/$f"' "$SHIP_LOCAL_REVIEW"; then
  echo "FAIL (dynamic command or handler-file scope is invalid)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "HOL scanner baseline remains strict and ASCII-safe... "
HOL_SCANNER_WORKFLOW="$ROOT_DIR/.github/workflows/hol-plugin-scanner.yml"
if ! HOL_SCANNER_POLICY=$(python3 -c 'import json, sys, yaml; workflow = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); steps = [step for job in workflow.get("jobs", {}).values() for step in job.get("steps", []) if str(step.get("uses", "")).startswith("hashgraph-online/ai-plugin-scanner-action@")]; len(steps) == 1 or sys.exit("expected exactly one HOL scanner action step"); settings = steps[0].get("with", {}); print(json.dumps({"min_score": int(settings.get("min_score", -1)), "fail_on_severity": settings.get("fail_on_severity")}))' "$HOL_SCANNER_WORKFLOW"); then
  echo "FAIL (active scanner policy could not be parsed)"
  ERRORS=$((ERRORS + 1))
elif ! jq -e '.min_score == 80 and .fail_on_severity == "high"' <<< "$HOL_SCANNER_POLICY" >/dev/null; then
  echo "FAIL (active scanner policy is not strict)"
  ERRORS=$((ERRORS + 1))
elif LC_ALL=C rg -q '[^\x00-\x7F]' "$E2E_TEST_EXECUTION"; then
  echo "FAIL (E2E guidance contains non-ASCII text that triggers scanner obfuscation detection)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Workflow re-entry rejects invalid persisted repository paths... "
REENTRY_FAILURE=""
assert_reentry_contract() {
  local label="$1"
  local file="$2"
  local reason="$3"

  local root_registration=false
  local root_match=false
  local slug_match=false

  if file_contains 'REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain' "$file" ||
     file_contains 'REGISTERED_WORKTREES=$(git -C "$RESOLVED_ORIGINAL_REPO_ROOT" worktree list --porcelain' "$file"; then
    root_registration=true
  fi
  if file_contains 'PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT' "$file" ||
     file_contains 'PERSISTED_ORIGINAL_REPO_ROOT" != "$RESOLVED_ORIGINAL_REPO_ROOT' "$file"; then
    root_match=true
  fi
  if file_contains 'PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG' "$file" ||
     file_contains 'PERSISTED_REPO_SLUG" != "$REPO_SLUG' "$file"; then
    slug_match=true
  fi

  if ! file_contains 'PERSISTED_ORIGINAL_REPO_ROOT' "$file" ||
     ! file_contains 'PERSISTED_WORKTREE_PATH' "$file" ||
     ! file_contains 'PERSISTED_REPO_SLUG' "$file" ||
     ! file_contains '[ -z "$PERSISTED_WORKTREE_PATH" ]' "$file" ||
     ! file_contains '[ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ]' "$file" ||
     ! file_contains '[ ! -d "$PERSISTED_WORKTREE_PATH" ]' "$file" ||
     [ "$root_registration" != "true" ] ||
     [ "$root_match" != "true" ] ||
     [ "$slug_match" != "true" ] ||
     ! file_contains "WORKFLOW_REASON=$reason" "$file" ||
     { ! file_contains 'set_loop_terminal_result "$STATE_FILE" "incomplete"' "$file" &&
       ! file_contains 'set_loop_terminal_result "$LOOP_STATE_FILE" "incomplete"' "$file"; }; then
    REENTRY_FAILURE="$label does not reject missing, relative, nonexistent, unregistered, or mismatched persisted paths"
  fi
}

assert_reentry_contract "start-issue" "$START_ISSUE_SKILL" "start-issue-worktree-path-invalid"
assert_reentry_contract "e2e-verify" "$E2E_LOOP_STATE" "e2e-worktree-path-invalid"
assert_reentry_contract "ship" "$SHIP_SKILL" "ship-worktree-path-invalid"
assert_reentry_contract "address-review" "$ADDRESS_REVIEW_LOOP_STATE" "address-review-worktree-path-invalid"

if [ -n "$REENTRY_FAILURE" ]; then
  echo "FAIL ($REENTRY_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Hard workflow invariants stop with machine-readable outcomes... "
INVARIANT_FAILURE=""

section_text() {
  local file="$1"
  local start="$2"
  local end="$3"

  awk -v start="$start" -v end="$end" '
    index($0, start) { active = 1 }
    active && index($0, end) && !index($0, start) { exit }
    active { print }
  ' "$file"
}

assert_invariant_section() {
  local label="$1"
  local file="$2"
  local start="$3"
  local end="$4"
  local reason="$5"
  local section

  section=$(section_text "$file" "$start" "$end")
  if [[ "$section" != *'WORKFLOW_RESULT=INCOMPLETE'* ]] ||
     [[ "$section" != *"WORKFLOW_REASON=$reason"* ]]; then
    INVARIANT_FAILURE="$label does not stop with reason $reason"
  fi
}

COVERAGE_ROUTER="$ROOT_DIR/plugins/go-workflow/lib/coverage/coverage-verification.md"
COVERAGE_GATE="$ROOT_DIR/plugins/go-workflow/lib/coverage/step-e-gate.md"
COVERAGE_GENERATION="$ROOT_DIR/plugins/go-workflow/lib/coverage/step-f-test-generation.md"
SHIP_SKILL="$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md"
SHIP_CI="$ROOT_DIR/plugins/go-workflow/lib/ship/ci-watch.md"
SHIP_MERGE="$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"
SHIP_ADDRESS="$ROOT_DIR/plugins/go-workflow/lib/ship/address-bots.md"
SHIP_REVIEW="$ROOT_DIR/plugins/go-workflow/lib/ship/local-review.md"
COMMIT_SKILL="$ROOT_DIR/plugins/go-workflow/skills/commit/SKILL.md"
CREATE_PR_SKILL="$ROOT_DIR/plugins/go-workflow/skills/create-pr/SKILL.md"
WORKTREE_REMOVE="$ROOT_DIR/plugins/go-workflow/skills/worktree/remove.md"
E2E_REBASE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/rebase-and-build.md"
E2E_SKILL="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md"
E2E_LOOP_STATE="$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/loop-state.md"
ADDRESS_REBASE="$ROOT_DIR/plugins/go-workflow/skills/address-review/checkout-rebase.md"
ADDRESS_SKILL="$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md"
REVIEW_DEEP_FIX="$ROOT_DIR/plugins/go-workflow/skills/review-deep/fix-and-verify.md"
START_ISSUE_SKILL="$ROOT_DIR/plugins/go-workflow/skills/start-issue/SKILL.md"

assert_invariant_section "low coverage" "$COVERAGE_GATE" \
  "### Branch 3" "### Branch 4" "coverage-below-threshold"
assert_invariant_section "missing tests" "$COVERAGE_GATE" \
  "### Branch 4" "### Branch 5" "coverage-no-tests"
assert_invariant_section "coverage test generation" "$COVERAGE_GENERATION" \
  "## Persist count and return" "__END__" \
  "coverage-test-generation-failed"
assert_invariant_section "CI registration timeout" "$SHIP_CI" \
  "## 10b." "## 10c." "ci-checks-not-registered"
assert_invariant_section "commit default branch" "$COMMIT_SKILL" \
  "### Step 2:" "### Step 3:" "default-branch"
assert_invariant_section "create-pr default branch" "$CREATE_PR_SKILL" \
  "### Step 2:" "### Step 3:" "default-branch"
assert_invariant_section "unsafe worktree removal" "$WORKTREE_REMOVE" \
  "**Unsafe removal**" "### Step 5:" "unsafe-worktree"
assert_invariant_section "E2E rebase conflict" "$E2E_REBASE" \
  "### 1c." "### 1d." "rebase-conflict"
assert_invariant_section "address-review rebase conflict" "$ADDRESS_REBASE" \
  '**If `$BEHIND` > 0:**' "## 1c." "rebase-conflict"
assert_invariant_section "ship rebase conflict" "$SHIP_ADDRESS" \
  "## 12a." "## 12b." "rebase-conflict"
assert_invariant_section "E2E generation failure" "$E2E_REBASE" \
  "### 2a." "### 2b." "generation-failed"
assert_invariant_section "E2E verification failure" "$E2E_REBASE" \
  "### 2b." "### 2c." "verification-failed"
assert_invariant_section "E2E post-fix verification failure" "$E2E_SKILL" \
  "### Re-verify after fixes" "## Step 4:" "verification-failed"
assert_invariant_section "review-deep verification failure" "$REVIEW_DEEP_FIX" \
  "## Verification" "## Commit" "verification-failed"
assert_invariant_section "ship generation failure" "$SHIP_REVIEW" \
  "### Codegen drift check" "### Per-language verification" "generation-failed"
assert_invariant_section "ship verification failure" "$SHIP_REVIEW" \
  "### Per-language verification" "## Step 7.5" "verification-failed"

LOW_COVERAGE_SECTION=$(section_text "$COVERAGE_GATE" "### Branch 3" "### Branch 5")
CI_REGISTRATION_SECTION=$(section_text "$SHIP_CI" "## 10b." "## 10c.")
WORKTREE_UNSAFE_SECTION=$(section_text "$WORKTREE_REMOVE" "**Unsafe removal**" "### Step 5:")
SHIP_FINAL_CHECKS=$(section_text "$SHIP_MERGE" "## 13a." "## 13b.")
SHIP_MERGEABILITY=$(section_text "$SHIP_MERGE" "## 13d." "## 13e.")
REVIEW_DEEP_VERIFICATION=$(section_text "$REVIEW_DEEP_FIX" "## Verification" "## Commit")
E2E_BUILD_VERIFICATION=$(section_text "$E2E_REBASE" "### 2b." "### 2c.")

if [[ "$LOW_COVERAGE_SECTION" == *"AskUserQuestion"* ]] ||
   [[ "$LOW_COVERAGE_SECTION" == *"Proceed without"* ]]; then
  INVARIANT_FAILURE="coverage failure still offers a bypass"
elif [[ "$CI_REGISTRATION_SECTION" == *"AskUserQuestion"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" == *"proceed without CI"* ]]; then
  INVARIANT_FAILURE="CI registration timeout still offers a bypass"
elif [[ "$CI_REGISTRATION_SECTION" != *"ci_skip_reason=no-applicable-workflow"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" != *"WORKFLOW_REASON=ci-checks-not-registered"* ]] ||
     [[ "$CI_REGISTRATION_SECTION" != *"WORKFLOW_REASON=ci-applicability-unknown"* ]]; then
  INVARIANT_FAILURE="CI registration does not distinguish inapplicable and missing checks"
elif [[ "$WORKTREE_UNSAFE_SECTION" == *"--force"* ]]; then
  INVARIANT_FAILURE="unsafe worktree removal still force-deletes"
elif [[ "$SHIP_FINAL_CHECKS" != *"WORKFLOW_REASON=unresolved-review-threads"* ]] ||
     [[ "$SHIP_FINAL_CHECKS" != *"WORKFLOW_REASON=human-changes-requested"* ]] ||
     [[ "$SHIP_FINAL_CHECKS" == *"ask how to proceed"* ]]; then
  INVARIANT_FAILURE="ship final review checks do not stop unconditionally"
elif [[ "$SHIP_MERGEABILITY" == *"AskUserQuestion"* ]] ||
     [[ "$SHIP_MERGEABILITY" != *'WORKFLOW_REASON="mergeability-unknown"'* ]] ||
     [[ "$SHIP_MERGEABILITY" != *'| `true` | `unstable` | **STOP.'* ]]; then
  INVARIANT_FAILURE="ship mergeability states still permit an invalid merge"
elif file_contains "commit to main anyway" "$COMMIT_SKILL" ||
     file_contains "default branch. Inform the user and ask how to proceed" "$SHIP_SKILL"; then
  INVARIANT_FAILURE="default-branch workflow still offers a bypass"
elif file_contains "Proceed with fixes WITHOUT rebasing" "$SHIP_ADDRESS" ||
     file_contains "proceed without rebasing" "$SHIP_SKILL"; then
  INVARIANT_FAILURE="ship can continue after an unresolved rebase"
elif ! file_contains 'set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"' "$ADDRESS_SKILL"; then
  INVARIANT_FAILURE="address-review rebase stops are not durable"
elif [[ "$REVIEW_DEEP_VERIFICATION" == *"|| true"* ]] ||
     [[ "$E2E_BUILD_VERIFICATION" == *"|| true"* ]]; then
  INVARIANT_FAILURE="verification failure is still ignored"
elif ! file_contains "cargo clippy --version" "$REVIEW_DEEP_FIX" ||
     ! file_contains "cargo clippy --version" "$SHIP_REVIEW"; then
  INVARIANT_FAILURE="Rust verification does not gate optional Clippy"
elif file_contains "Skipping codegen check" "$E2E_REBASE" ||
     file_contains "Skipping codegen check" "$SHIP_REVIEW"; then
  INVARIANT_FAILURE="generation failure is still ignored"
elif ! file_contains "Only source-free changes" "$COVERAGE_ROUTER"; then
  INVARIANT_FAILURE="coverage router does not constrain skip behavior"
elif file_contains 'Coverage verified or skipped (per `--skip-coverage` flag)' "$START_ISSUE_SKILL" ||
     file_contains 'execute the ship workflow with `--skip-coverage`' "$E2E_FINISH"; then
  INVARIANT_FAILURE="a completion path still waives changed-source coverage"
fi

if [ -n "$INVARIANT_FAILURE" ]; then
  echo "FAIL ($INVARIANT_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "E2E failures persist a terminal result before exiting... "
E2E_TERMINAL_FAILURE=""
for e2e_failure_state in \
  fail \
  partial \
  skipped-server-failed \
  missing-browser-tooling \
  uninspected-screenshots; do
  if ! grep -Fq "\`$e2e_failure_state\`" "$E2E_FINISH"; then
    E2E_TERMINAL_FAILURE="E2E terminal gate omits $e2e_failure_state"
    break
  fi
done

E2E_PROMISE_LINE=$(grep -nF 'set_loop_terminal_result "$STATE_FILE" "e2e-fail" "$WORKFLOW_REASON" "e2e-failed" "E2E_FAIL"' "$E2E_FINISH" | head -1 | cut -d: -f1 || true)
E2E_PERSIST_LINE="$E2E_PROMISE_LINE"
E2E_MARKER_LINE=$(grep -nF 'echo "<done>E2E_FAIL</done>"' "$E2E_FINISH" | head -1 | cut -d: -f1 || true)
E2E_TERMINAL_REENTRY=$(section_text "$E2E_LOOP_STATE" "## Terminal Re-entry" "## Persist Build Result")
E2E_REENTRY_MARKERS=$(grep -cF 'echo "<done>' <<< "$E2E_TERMINAL_REENTRY" || true)

if [ -n "$E2E_TERMINAL_FAILURE" ]; then
  echo "FAIL ($E2E_TERMINAL_FAILURE)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains 'WORKFLOW_RESULT=e2e-fail' "$E2E_FINISH" ||
     ! file_contains 'WORKFLOW_REASON="$E2E_RESULT"' "$E2E_FINISH" ||
     ! file_contains 'set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "e2e-fail" "$WORKFLOW_REASON" "e2e-failed"' "$E2E_FINISH" ||
     [ -z "$E2E_PROMISE_LINE" ] ||
     [ -z "$E2E_PERSIST_LINE" ] ||
     [ -z "$E2E_MARKER_LINE" ]; then
  echo "FAIL (E2E terminal state persistence is incomplete)"
  ERRORS=$((ERRORS + 1))
elif [ "$E2E_PERSIST_LINE" -ge "$E2E_MARKER_LINE" ] ||
     [ "$E2E_PROMISE_LINE" -ge "$E2E_MARKER_LINE" ]; then
  echo "FAIL (E2E terminal marker precedes durable state persistence)"
  ERRORS=$((ERRORS + 1))
elif ! file_contains '`e2e-failed`' "$E2E_SKILL" ||
     [[ "$E2E_TERMINAL_REENTRY" != *'get_loop_field "$STATE_FILE" "reason" "$WORKFLOW_STATE_PATH"'* ]] ||
     [[ "$E2E_TERMINAL_REENTRY" != *'echo "E2E verification failed: $WORKFLOW_REASON"'* ]] ||
     [[ "$E2E_TERMINAL_REENTRY" != *'echo "<done>E2E_FAIL</done>"'* ]] ||
     [ "$E2E_REENTRY_MARKERS" -ne 1 ] ||
     [[ "$E2E_TERMINAL_REENTRY" != *'exit 0'* ]]; then
  echo "FAIL (E2E terminal re-entry can resume work or emit another promise)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

if ! "$ROOT_DIR/scripts/test-go-web-templates.sh"; then
  ERRORS=$((ERRORS + 1))
fi

echo -n "Command files have valid YAML frontmatter... "
if [ $ERRORS -gt 0 ]; then
  echo "FAIL ($ERRORS of $TOTAL)"
  printf "$INVALID\n"
else
  echo "OK ($TOTAL commands)"
fi

echo ""

echo -n "Database templates keep initialization instance-scoped and leak-free... "
DB_TEMPLATE_FAILURE=""
DB_TEMPLATES=(
  "$ROOT_DIR/plugins/go-web/templates/db/database.postgres.go:goose.DialectPostgres"
  "$ROOT_DIR/plugins/go-web/templates/db/database.sqlite.go:goose.DialectSQLite3"
  "$ROOT_DIR/plugins/go-web/templates/db/database.mysql.go:goose.DialectMySQL"
)

for entry in "${DB_TEMPLATES[@]}"; do
  file="${entry%%:*}"
  dialect="${entry#*:}"
  open_line=$(grep -nE 'pool, err := pgxpool.New|conn, err := sql.Open' "$file" | head -1 | cut -d: -f1)
  cleanup_line=$(grep -nE 'defer func\(\)' "$file" | head -1 | cut -d: -f1)
  ping_line=$(grep -nE 'Ping(Context)?\(ctx\)' "$file" | head -1 | cut -d: -f1)
  migration_line=$(grep -nE 'db\.migrate\(ctx\)' "$file" | head -1 | cut -d: -f1)

  if [ -z "$open_line" ] || [ -z "$cleanup_line" ] || [ -z "$ping_line" ] || [ -z "$migration_line" ] ||
     [ "$cleanup_line" -le "$open_line" ] || [ "$cleanup_line" -ge "$ping_line" ] || [ "$cleanup_line" -ge "$migration_line" ]; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not guard every post-open failure with cleanup"
    break
  fi
  if ! grep -Fq "goose.NewProvider(" "$file" ||
     ! grep -Fq "$dialect" "$file" ||
     ! grep -Fq 'goose.WithDisableGlobalRegistry(true)' "$file" ||
     ! grep -Fq 'provider.Up(ctx)' "$file" ||
     ! grep -Fq 'fs.Sub(migrationsFS, "migrations")' "$file"; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not use a context-aware instance provider"
    break
  fi
  if ! grep -Fq 'func (db *DB) Close() error' "$file"; then
    DB_TEMPLATE_FAILURE="${file#"$ROOT_DIR"/} does not expose shutdown errors consistently"
    break
  fi
done

if [ -z "$DB_TEMPLATE_FAILURE" ] && grep -nE 'goose\.(SetBaseFS|SetDialect|Up)\(' "${DB_TEMPLATES[@]%%:*}" >/dev/null; then
  DB_TEMPLATE_FAILURE="database templates still mutate goose package globals"
fi
if [ -z "$DB_TEMPLATE_FAILURE" ] &&
   { ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close database: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.sqlite.go" ||
     ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close database: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.mysql.go" ||
     ! grep -Fq 'errors.Join(err, fmt.Errorf("failed to close migration connection: %w", closeErr))' "$ROOT_DIR/plugins/go-web/templates/db/database.postgres.go"; }; then
  DB_TEMPLATE_FAILURE="database close errors are not preserved"
fi
if [ -z "$DB_TEMPLATE_FAILURE" ] &&
   { ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/main.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.postgres.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.sqlite.go" ||
     ! grep -Fq 'if err := db.Close(); err != nil {' "$ROOT_DIR/plugins/go-web/templates/app/testutil.mysql.go"; }; then
  DB_TEMPLATE_FAILURE="generated shutdown call sites discard database close errors"
fi

if [ -n "$DB_TEMPLATE_FAILURE" ]; then
  echo "FAIL ($DB_TEMPLATE_FAILURE)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo ""

echo -n "Gemini image defaults and request tiers are valid... "
GEMINI_IMAGE_DIR="$ROOT_DIR/plugins/llm-tools/skills/gemini-image"
GEMINI_COMMAND="$ROOT_DIR/plugins/llm-tools/commands/gemini-image.md"

if grep -Rqs 'gemini-3\.1-flash-image-preview' "$GEMINI_IMAGE_DIR" "$GEMINI_COMMAND"; then
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

  DEFAULT_REQUEST=$(env -u GEMINI_MODEL -u GEMINI_SERVICE_TIER GEMINI_PROMPT=test "$BASH" "$BUILD_BLOCK")
  UNSUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-3.1-flash-image GEMINI_SERVICE_TIER=priority GEMINI_PROMPT=test "$BASH" "$BUILD_BLOCK")
  SUPPORTED_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=PRIORITY GEMINI_PROMPT=test "$BASH" "$BUILD_BLOCK")
  INVALID_REQUEST=$(GEMINI_MODEL=gemini-2.5-flash-image GEMINI_SERVICE_TIER=express GEMINI_IMAGE_SIZE=4K GEMINI_PROMPT=test "$BASH" "$BUILD_BLOCK")

  if ! grep -q 'os.environ.get("GEMINI_MODEL", "gemini-3\.1-flash-image")' "$GEMINI_IMAGE_DIR/request-builder.md"; then
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
