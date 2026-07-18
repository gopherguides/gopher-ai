#!/bin/bash

set -euo pipefail

CLAUDE_CMD="${GOPHER_AI_TMUX_CLAUDE_CMD:-claude --dangerously-skip-permissions}"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'USAGE'
Usage:
  tmux-start.sh <issue-number> [--copy-env|--no-copy-env] [--claude-cmd <command>]

Set GOPHER_AI_TMUX_CLAUDE_CMD to override the default Claude launch command.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not installed"
}

slugify_window() {
  printf '%s\n' "$1" \
    | sed 's/[^a-zA-Z0-9]/-/g' \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/--*/-/g; s/^-//; s/-$//' \
    | cut -c1-40 \
    | sed 's/-$//'
}

find_existing_window() {
  local canonical_name="$1"
  local legacy_name="$2"
  local canonical_match=""
  local legacy_match=""
  local window_name

  while IFS= read -r window_name; do
    if [ "$window_name" = "$canonical_name" ] && [ -z "$canonical_match" ]; then
      canonical_match="$window_name"
    elif [ "$window_name" = "$legacy_name" ] && [ -z "$legacy_match" ]; then
      legacy_match="$window_name"
    fi
  done

  if [ -n "$canonical_match" ]; then
    printf '%s\n' "$canonical_match"
  elif [ -n "$legacy_match" ]; then
    printf '%s\n' "$legacy_match"
  fi
}

wait_for_claude_ready() {
  local window_name="$1"
  local launch_marker="$2"
  local last_content=""
  local stable_count=0
  local pane_content
  sleep 5
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    sleep 2
    pane_content=$(tmux capture-pane -t "$window_name" -p 2>/dev/null || true)
    if printf '%s\n' "$pane_content" | grep -qE '(^[[:space:]]*>[[:space:]]*$|Bypassing Permissions|Welcome to Claude Code|claude[[:space:]]*>|Try .* for shortcuts)'; then
      return 0
    fi
    if printf '%s\n' "$pane_content" | grep -qF "$launch_marker" && [ "$pane_content" = "$last_content" ]; then
      stable_count=$((stable_count + 1))
    else
      stable_count=0
    fi
    if [ "$stable_count" -ge 3 ]; then
      return 0
    fi
    last_content="$pane_content"
  done
  return 1
}

if [ "${GOPHER_AI_TMUX_START_SOURCE_ONLY:-false}" = "true" ]; then
  return 0
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

ISSUE_NUM="${1:-}"
[ -n "$ISSUE_NUM" ] || { usage >&2; exit 1; }
shift
echo "$ISSUE_NUM" | grep -qE '^[0-9]+$' || die "Issue number must be numeric"

COPY_ENV="false"
while [ $# -gt 0 ]; do
  case "$1" in
    --copy-env)
      COPY_ENV="true"
      shift
      ;;
    --no-copy-env)
      COPY_ENV="false"
      shift
      ;;
    --claude-cmd)
      CLAUDE_CMD="${2:-}"
      [ -n "$CLAUDE_CMD" ] || die "--claude-cmd requires a command"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[ -n "${TMUX:-}" ] || die "Not running inside a tmux session. Start one with: tmux new-session -s work"
require_tool gh
require_tool git
require_tool jq
require_tool tmux
gh auth status >/dev/null 2>&1 || die "gh not authenticated. Run: gh auth login"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"

SOURCE_DIR=$(pwd)
METADATA_FILE=$(mktemp "${TMPDIR:-/tmp}/gopher-ai-tmux-start.XXXXXX")
trap 'rm -f "$METADATA_FILE"' EXIT

if [ "$COPY_ENV" = "true" ]; then
  "$SCRIPT_DIR/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --copy-env --metadata-file "$METADATA_FILE"
else
  "$SCRIPT_DIR/worktree-create.sh" create "$ISSUE_NUM" --source-dir "$SOURCE_DIR" --no-copy-env --metadata-file "$METADATA_FILE"
fi

ITEM_TITLE=""
REPO_NAME=""
WORKTREE_ABS_PATH=""
BRANCH_NAME=""
while IFS=$'\t' read -r key value; do
  case "$key" in
    ITEM_TITLE) ITEM_TITLE="$value" ;;
    REPO_NAME) REPO_NAME="$value" ;;
    WORKTREE_ABS_PATH) WORKTREE_ABS_PATH="$value" ;;
    BRANCH_NAME) BRANCH_NAME="$value" ;;
  esac
done < "$METADATA_FILE"

[ -n "$ITEM_TITLE" ] || die "Missing item title from worktree metadata"
[ -n "$REPO_NAME" ] || die "Missing repo name from worktree metadata"
[ -n "$WORKTREE_ABS_PATH" ] || die "Missing worktree path from worktree metadata"
[ -n "$BRANCH_NAME" ] || die "Missing branch name from worktree metadata"

WINDOW_SLUG=$(slugify_window "$ITEM_TITLE")
[ -n "$WINDOW_SLUG" ] || WINDOW_SLUG="$ISSUE_NUM"
WINDOW_NAME="${REPO_NAME}-issue-${ISSUE_NUM}-${WINDOW_SLUG}"

LEGACY_WINDOW_NAME="${REPO_NAME}-issue-${ISSUE_NUM}"
EXISTING_WINDOW=$(tmux list-windows -F '#{window_name}' 2>/dev/null | find_existing_window "$WINDOW_NAME" "$LEGACY_WINDOW_NAME" || true)
if [ -n "$EXISTING_WINDOW" ]; then
  tmux select-window -t "$EXISTING_WINDOW"
  echo "Switched to existing tmux window: $EXISTING_WINDOW"
  echo "Worktree: $WORKTREE_ABS_PATH"
  exit 0
fi

LAUNCH_MARKER="GOPHER_AI_CLAUDE_LAUNCHED_${ISSUE_NUM}"
LAUNCH_COMMAND=$(printf 'cd %q && printf "\\n%s\\n" && %s' "$WORKTREE_ABS_PATH" "$LAUNCH_MARKER" "$CLAUDE_CMD")

tmux new-window -n "$WINDOW_NAME"
tmux send-keys -t "$WINDOW_NAME" "$LAUNCH_COMMAND" Enter
echo "Created tmux window: $WINDOW_NAME"

if wait_for_claude_ready "$WINDOW_NAME" "$LAUNCH_MARKER"; then
  echo "Claude Code appears ready."
else
  echo "Warning: Claude Code did not expose a clear ready signal before timeout. Sending start command after settle wait."
fi

tmux send-keys -t "$WINDOW_NAME" "/go-workflow:start-issue $ISSUE_NUM" Enter

cat <<EOF
--- tmux-start complete ---

Issue:     #$ISSUE_NUM
Worktree:  $WORKTREE_ABS_PATH
Branch:    $BRANCH_NAME
Window:    $WINDOW_NAME

Switch to it:
  Ctrl+B w          (window picker)
  Ctrl+B <number>   (direct switch by window index)

Claude Code is running /go-workflow:start-issue $ISSUE_NUM autonomously.
Monitor the window and accept plans when prompted.
EOF
