#!/bin/bash
# Bounded regression for the Bash 5.3 here-string hang, also run on system Bash.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/session-start.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/home/.codex/skills/owned" "$TEST_ROOT/plugin/hooks" "$TEST_ROOT/plugin/.codex-plugin"
printf '%s\n' '---' 'name: owned' 'description: legacy fixture' '---' > "$TEST_ROOT/home/.codex/skills/owned/SKILL.md"
printf '%s\n' '{"version":"test"}' > "$TEST_ROOT/plugin/.codex-plugin/plugin.json"
HASH=$(shasum -a 256 "$TEST_ROOT/home/.codex/skills/owned/SKILL.md" | awk '{print $1}')
printf '%s owned\n' "$HASH" > "$TEST_ROOT/plugin/hooks/legacy-skill-hashes.txt"
# A large manifest makes synchronous here-string pipe writes block reliably.
awk 'BEGIN { for (i=0; i<2000; i++) printf "unused unused-%04d\n", i }' >> "$TEST_ROOT/plugin/hooks/legacy-skill-hashes.txt"
cp "$ROOT_DIR/plugins/go-workflow/hooks/codex-cleanup-on-start.sh" "$TEST_ROOT/plugin/hooks/"
for interpreter in /bin/bash "$(command -v bash)" /opt/homebrew/bin/bash; do
  [ -x "$interpreter" ] || continue
  mkdir -p "$TEST_ROOT/home/.codex/skills/owned"
  printf '%s\n' '---' 'name: owned' 'description: legacy fixture' '---' > "$TEST_ROOT/home/.codex/skills/owned/SKILL.md"
  rm -f "$TEST_ROOT/home/.codex/.gopher-ai-cleanup-v3-test"
  HOME="$TEST_ROOT/home" CLAUDE_PLUGIN_ROOT="$TEST_ROOT/plugin" \
    python3 "$SCRIPT_DIR/run-with-timeout.py" 5 "$interpreter" "$TEST_ROOT/plugin/hooks/codex-cleanup-on-start.sh"
  test ! -d "$TEST_ROOT/home/.codex/skills/owned"
  test -f "$TEST_ROOT/home/.codex/.gopher-ai-cleanup-v3-test"
done
echo "SessionStart interpreter regression passed"
