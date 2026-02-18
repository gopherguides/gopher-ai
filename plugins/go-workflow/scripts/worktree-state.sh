#!/bin/bash
# Worktree state management for go-workflow
# Tracks active worktree path so the pre-tool-use hook can block
# tool calls that accidentally target the original repo.
#
# Usage:
#   worktree-state.sh save <worktree_abs_path> <original_path> <issue_num>
#   worktree-state.sh get
#   worktree-state.sh clear

set -euo pipefail

STATE_FILE="${HOME}/.claude/worktree-state.json"

save_state() {
  local worktree_path="$1"
  local original_path="$2"
  local issue_num="$3"
  local created
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "$(dirname "$STATE_FILE")"
  jq -n \
    --arg wt "$worktree_path" \
    --arg orig "$original_path" \
    --arg issue "$issue_num" \
    --arg ts "$created" \
    '{worktree_path: $wt, original_path: $orig, issue: $issue, created: $ts}' \
    > "$STATE_FILE"
  echo "Worktree state saved: ${worktree_path}"
}

get_state() {
  if [ -f "$STATE_FILE" ]; then
    cat "$STATE_FILE"
  else
    echo "{}"
  fi
}

clear_state() {
  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
    echo "Worktree state cleared"
  else
    echo "No worktree state to clear"
  fi
}

case "${1:-}" in
  save)
    if [ $# -lt 4 ]; then
      echo "Usage: worktree-state.sh save <worktree_path> <original_path> <issue_num>" >&2
      exit 1
    fi
    save_state "$2" "$3" "$4"
    ;;
  get)
    get_state
    ;;
  clear)
    clear_state
    ;;
  *)
    echo "Usage: worktree-state.sh {save|get|clear}" >&2
    exit 1
    ;;
esac
