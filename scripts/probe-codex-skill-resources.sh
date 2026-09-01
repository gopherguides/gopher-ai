#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_BASE="${TMPDIR:?TMPDIR must point to the Detent temporary directory}"

case "$TMP_BASE" in
  "$ROOT_DIR/.detent/tmp"|"$ROOT_DIR/.detent/tmp/"*) ;;
  *)
    printf 'FAIL: TMPDIR must be inside %s/.detent/tmp\n' "$ROOT_DIR" >&2
    exit 1
    ;;
esac

command -v codex >/dev/null 2>&1 || {
  printf 'FAIL: codex is required\n' >&2
  exit 1
}

PROBE_DIR=$(mktemp -d "${TMP_BASE%/}/gopher-ai-codex-resources.XXXXXX")
LAST_MESSAGE="$PROBE_DIR/last-message.txt"
EVENT_LOG="$PROBE_DIR/events.log"
TIMEOUT_MARKER="$PROBE_DIR/timeout"
mkdir -p "$PROBE_DIR/.agents/skills"
ln -s "$ROOT_DIR/plugins/go-workflow/skills/commit" "$PROBE_DIR/.agents/skills/commit"
ln -s "$ROOT_DIR/plugins/gopher-guides/skills/gopher-guides" "$PROBE_DIR/.agents/skills/gopher-guides"
ln -s "$ROOT_DIR/plugins/go-web/skills/convert-to-go-project" "$PROBE_DIR/.agents/skills/convert-to-go-project"

env -u PLUGIN_ROOT -u PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u GOPHER_GUIDES_API_KEY codex exec \
  --cd "$PROBE_DIR" \
  --ephemeral \
  --ignore-user-config \
  --skip-git-repo-check \
  --sandbox read-only \
  --output-last-message "$LAST_MESSAGE" \
  - >"$EVENT_LOG" 2>&1 <<'PROMPT' &
Invoke `$commit`, `$gopher-guides`, and `$convert-to-go-project` for this read-only resource-resolution probe. Do not edit files, use the network, call an API, or request credentials.

For each selected skill, use the absolute selected `SKILL.md` path exposed by Codex and follow its Plugin Resource Resolution contract. Do not use or infer any plugin-root environment variable.

Use read-only shell commands to perform these checks:

1. Derive the go-workflow plugin root, require that it is non-empty and absolute, and read the first line of `<PLUGIN_ROOT>/lib/driver-interaction.md`. Require that the file is readable.
2. Derive the gopher-guides plugin root, require that it is non-empty and absolute, and require that `<PLUGIN_ROOT>/scripts/cache-api.sh` is executable.
3. Derive the go-web plugin root, require that it is non-empty and absolute, and read the first line of `<PLUGIN_ROOT>/references/convert-to-go-project.md`. Require the exact text `# Convert to Go Project`.
4. Invoke the cache wrapper with no arguments. Require a non-zero status and the exact stderr text `Usage: cache-api.sh <endpoint> <json-data>`.
5. Invoke it with `practices` and `{"topic":"resource probe"}` while `GOPHER_GUIDES_API_KEY` is unset. Require a non-zero status and the exact stderr text `Error: GOPHER_GUIDES_API_KEY is not set`.

Only after all checks pass, respond with exactly these six plain-text lines, replacing each root placeholder with the concrete absolute root:

GO_WORKFLOW_PLUGIN_ROOT=<absolute-root>
GO_WORKFLOW_RESOURCE=readable
GOPHER_GUIDES_PLUGIN_ROOT=<absolute-root>
GOPHER_GUIDES_USAGE=Usage: cache-api.sh <endpoint> <json-data>
GO_WEB_PLUGIN_ROOT=<absolute-root>
GO_WEB_CONVERSION_RESOURCE=# Convert to Go Project
PROMPT
PROBE_PID=$!

(
  sleep 60
  if kill -0 "$PROBE_PID" 2>/dev/null; then
    : > "$TIMEOUT_MARKER"
    kill "$PROBE_PID" 2>/dev/null || true
  fi
) &
WATCHDOG_PID=$!

set +e
wait "$PROBE_PID"
PROBE_STATUS=$?
set -e
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

if [ -f "$TIMEOUT_MARKER" ]; then
  printf 'FAIL: live Codex resource probe timed out\n' >&2
  sed -n '1,160p' "$EVENT_LOG" >&2
  exit 1
fi
if [ "$PROBE_STATUS" -ne 0 ]; then
  printf 'FAIL: live Codex resource probe exited with status %s\n' "$PROBE_STATUS" >&2
  sed -n '1,160p' "$EVENT_LOG" >&2
  exit 1
fi

GO_WORKFLOW_PLUGIN_ROOT=$(sed -n 's/^GO_WORKFLOW_PLUGIN_ROOT=//p' "$LAST_MESSAGE")
GOPHER_GUIDES_PLUGIN_ROOT=$(sed -n 's/^GOPHER_GUIDES_PLUGIN_ROOT=//p' "$LAST_MESSAGE")
GO_WEB_PLUGIN_ROOT=$(sed -n 's/^GO_WEB_PLUGIN_ROOT=//p' "$LAST_MESSAGE")

case "$GO_WORKFLOW_PLUGIN_ROOT" in
  /*) ;;
  *)
    printf 'FAIL: missing absolute go-workflow root evidence\n' >&2
    sed -n '1,160p' "$EVENT_LOG" >&2
    exit 1
    ;;
esac

case "$GOPHER_GUIDES_PLUGIN_ROOT" in
  /*) ;;
  *)
    printf 'FAIL: missing absolute gopher-guides root evidence\n' >&2
    sed -n '1,160p' "$EVENT_LOG" >&2
    exit 1
    ;;
esac

case "$GO_WEB_PLUGIN_ROOT" in
  /*) ;;
  *)
    printf 'FAIL: missing absolute go-web root evidence\n' >&2
    sed -n '1,160p' "$EVENT_LOG" >&2
    exit 1
    ;;
esac

test -r "$GO_WORKFLOW_PLUGIN_ROOT/lib/driver-interaction.md" || {
  printf 'FAIL: resolved go-workflow resource is not readable\n' >&2
  exit 1
}
test "$GO_WORKFLOW_PLUGIN_ROOT" = "$ROOT_DIR/plugins/go-workflow" || {
  printf 'FAIL: go-workflow probe resolved a different installation\n' >&2
  exit 1
}
test -x "$GOPHER_GUIDES_PLUGIN_ROOT/scripts/cache-api.sh" || {
  printf 'FAIL: resolved gopher-guides cache wrapper is not executable\n' >&2
  exit 1
}
test "$GOPHER_GUIDES_PLUGIN_ROOT" = "$ROOT_DIR/plugins/gopher-guides" || {
  printf 'FAIL: gopher-guides probe resolved a different installation\n' >&2
  exit 1
}
test -r "$GO_WEB_PLUGIN_ROOT/references/convert-to-go-project.md" || {
  printf 'FAIL: resolved go-web conversion workflow is not readable\n' >&2
  exit 1
}
test "$GO_WEB_PLUGIN_ROOT" = "$ROOT_DIR/plugins/go-web" || {
  printf 'FAIL: go-web probe resolved a different installation\n' >&2
  exit 1
}
rg -Fxq 'GO_WORKFLOW_RESOURCE=readable' "$LAST_MESSAGE" || {
  printf 'FAIL: missing go-workflow resource evidence\n' >&2
  exit 1
}
rg -Fxq 'GOPHER_GUIDES_USAGE=Usage: cache-api.sh <endpoint> <json-data>' "$LAST_MESSAGE" || {
  printf 'FAIL: missing gopher-guides usage evidence\n' >&2
  exit 1
}
rg -Fxq 'GO_WEB_CONVERSION_RESOURCE=# Convert to Go Project' "$LAST_MESSAGE" || {
  printf 'FAIL: missing go-web conversion resource evidence\n' >&2
  exit 1
}

printf 'Codex skill resource probe passed\n'
printf '  go-workflow: %s\n' "$GO_WORKFLOW_PLUGIN_ROOT/lib/driver-interaction.md"
printf '  gopher-guides: %s\n' "$GOPHER_GUIDES_PLUGIN_ROOT/scripts/cache-api.sh"
printf '  go-web: %s\n' "$GO_WEB_PLUGIN_ROOT/references/convert-to-go-project.md"
