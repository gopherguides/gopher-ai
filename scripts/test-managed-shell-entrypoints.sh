#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
ERRORS=0

require_text() {
  local text="$1"
  local file="$2"
  local label="$3"

  if ! grep -Fq -- "$text" "$file"; then
    printf 'FAIL: %s\n' "$label"
    ERRORS=$((ERRORS + 1))
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local label="$3"

  if grep -Eq -- "$pattern" "$file"; then
    printf 'FAIL: %s\n' "$label"
    ERRORS=$((ERRORS + 1))
  fi
}

echo "=== Managed Shell Entrypoint Tests ==="

for gate in test-commands test-hooks test-ship-e2e-gate check-shared-sync; do
  require_text "/bin/bash ./scripts/$gate.sh" "$ROOT_DIR/detent.yaml" \
    "Detent gate must launch $gate through /bin/bash"
done

require_text '/bin/bash "$PLANNER"' "$ROOT_DIR/scripts/test-review-plan.sh" \
  "review planner test must use an explicit interpreter"
require_text '/bin/bash "$SELECTOR"' "$ROOT_DIR/scripts/test-ship-ollama-model.sh" \
  "Ollama selector test must use an explicit interpreter"
if [ "$(grep -c '^#!/bin/bash$' "$ROOT_DIR/scripts/test-ship-ollama-model.sh")" -ne 1 ]; then
  printf 'FAIL: %s\n' "Ollama fixture commands must use Bash ENOEXEC fallback in managed workers"
  ERRORS=$((ERRORS + 1))
fi
require_text '/bin/bash "$REVIEW_SCRIPT"' "$ROOT_DIR/scripts/test-gopher-ai-review-action.sh" \
  "review action test must use an explicit interpreter"
if [ "$(grep -c '^#!/usr/bin/env bash$' "$ROOT_DIR/scripts/test-gopher-ai-review-action.sh")" -ne 1 ]; then
  printf 'FAIL: %s\n' "review action fixture commands must use Bash ENOEXEC fallback in managed workers"
  ERRORS=$((ERRORS + 1))
fi
require_text '/bin/bash "$LAUNCHER"' "$ROOT_DIR/scripts/test-tmux-start.sh" \
  "tmux launcher test must use an explicit interpreter"
if [ "$(grep -c '^#!/bin/bash$' "$ROOT_DIR/scripts/test-tmux-start.sh")" -ne 1 ]; then
  printf 'FAIL: %s\n' "tmux fixture commands must use Bash ENOEXEC fallback in managed workers"
  ERRORS=$((ERRORS + 1))
fi
require_text '/bin/bash "$ROOT_DIR/scripts/test-go-web-templates.sh"' "$ROOT_DIR/scripts/test-commands.sh" \
  "nested Go web test must use an explicit interpreter"
require_text '/bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh"' \
  "$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md" \
  "ship bootstrap must use an explicit interpreter"
require_text 'python3 "$VALIDATOR"' "$ROOT_DIR/scripts/test-go-dev-codex-skills.sh" \
  "Go skill validator tests must use an explicit interpreter"
reject_pattern '&& "\$VALIDATOR"' "$ROOT_DIR/scripts/test-go-dev-codex-skills.sh" \
  "Go skill validator tests must not execute the repository entrypoint directly"
reject_pattern "printf '%s\\\\n' '#!/bin/sh'" "$ROOT_DIR/scripts/test-llm-tools-codex-skills.sh" \
  "LLM provider fixtures must use Bash ENOEXEC fallback in managed workers"
require_text '/bin/bash "$ROOT_DIR/scripts/run-go-tests.sh"' \
  "$ROOT_DIR/scripts/test-go-web-templates.sh" \
  "generated Go fixture tests must use the managed-worker runner"
require_text 'Managed Darwin worker compiled Go tests' \
  "$ROOT_DIR/scripts/test-go-web-templates.sh" \
  "generated Go fixtures must recognize compile-only managed-worker validation"
require_text '/bin/bash ../../../scripts/run-go-tests.sh ./...' "$ROOT_DIR/detent.yaml" \
  "Detent demo tests must use the managed-worker runner"
require_text 'go build -o "$TMPDIR/gopher-ai-demo"' "$ROOT_DIR/detent.yaml" \
  "Detent demo binaries must remain in the managed temporary directory"
reject_pattern '\$\("\$SCRIPT_DIR/cache-mutate\.sh"' \
  "$ROOT_DIR/plugins/gopher-guides/scripts/cache-api.sh" \
  "cache API must not directly execute its mutation helper"
reject_pattern '^[[:space:]]*"\$SCRIPT_DIR/cache-lock\.sh"' \
  "$ROOT_DIR/plugins/gopher-guides/scripts/cache-api.sh" \
  "cache API must not directly execute its lock helper"
reject_pattern '^[[:space:]]*"\$SCRIPT_DIR/cache-lock\.sh"' \
  "$ROOT_DIR/plugins/gopher-guides/scripts/clear-cache.sh" \
  "cache clearing must not directly execute its lock helper"
require_text '!`/bin/bash "${CLAUDE_PLUGIN_ROOT}/scripts/clear-cache.sh"`' \
  "$ROOT_DIR/plugins/gopher-guides/commands/clear-cache.md" \
  "Claude cache clearing must use an explicit interpreter"
require_text '/bin/bash "<PLUGIN_ROOT>/scripts/clear-cache.sh"' \
  "$ROOT_DIR/plugins/gopher-guides/skills/clear-cache/SKILL.md" \
  "Codex cache clearing must use an explicit interpreter"
require_text '/bin/bash "<PLUGIN_ROOT>/scripts/cache-api.sh"' \
  "$ROOT_DIR/plugins/gopher-guides/skills/gopher-guides/SKILL.md" \
  "Gopher Guides API calls must use an explicit interpreter"

reject_pattern '(^|[|&;(])[[:space:]]*"\$(worktree_state|cache_lock|cache_api|clear_cache_script)"' \
  "$ROOT_DIR/scripts/test-hooks.sh" \
  "hook tests must not directly execute repository shell helpers"
reject_pattern 'HOME="\$[^ ]+"[[:space:]]+"\$(worktree_state|cache_api)"' \
  "$ROOT_DIR/scripts/test-hooks.sh" \
  "hook tests with environment overrides must use an explicit interpreter"
reject_pattern '\|[[:space:]]*"\$CORE_STOP_HOOK"' "$ROOT_DIR/scripts/test-hooks.sh" \
  "stop hook tests must use an explicit interpreter"
reject_pattern 'env -u CLAUDE_SESSION_ID "\$ROOT_DIR/shared/scripts/setup-loop\.sh"' \
  "$ROOT_DIR/scripts/test-hooks.sh" \
  "loop setup tests must use an explicit interpreter"
reject_pattern '#!/bin/sh' "$ROOT_DIR/scripts/test-hooks.sh" \
  "hook fixture commands must use Bash ENOEXEC fallback in managed workers"
if [ "$(grep -c '^#!/bin/bash$' "$ROOT_DIR/scripts/test-hooks.sh")" -ne 1 ]; then
  printf 'FAIL: %s\n' "hook fixture commands must not include executable shebangs"
  ERRORS=$((ERRORS + 1))
fi

require_text '"/bin/bash",' \
  "$ROOT_DIR/scripts/test-codex-skill-names.py" \
  "Python installer probes must use an explicit interpreter"
reject_pattern '\[str\(ROOT_DIR / "scripts/install-codex\.sh"\)' \
  "$ROOT_DIR/scripts/test-codex-skill-names.py" \
  "Python installer probes must not execute the repository script directly"

if [ "$ERRORS" -gt 0 ]; then
  printf 'Managed shell entrypoint tests failed: %s\n' "$ERRORS"
  exit 1
fi

echo "Managed shell entrypoint tests passed."
