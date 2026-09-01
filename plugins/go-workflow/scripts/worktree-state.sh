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

LEGACY_STATE_FILE="${HOME}/.claude/worktree-state.json"

repository_state_file() {
  local repository_path="${1:-.}"
  local common_dir repository_root
  common_dir=$(git -C "$repository_path" rev-parse --git-common-dir 2>/dev/null) || return 1
  case "$common_dir" in
    /*)
      ;;
    *)
      repository_root=$(git -C "$repository_path" rev-parse --show-toplevel 2>/dev/null) || return 1
      common_dir=$(cd "$repository_root" && cd "$common_dir" && pwd -P) || return 1
      ;;
  esac
  printf '%s/gopher-ai/worktree-state.json\n' "${common_dir%/}"
}

save_state() {
  local worktree_path="$1"
  local original_path="$2"
  local issue_num="$3"
  local created state_file
  state_file=$(repository_state_file "$original_path") || {
    echo "Error: original path is not a Git repository: $original_path" >&2
    return 1
  }
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "$(dirname "$state_file")"
  jq -n \
    --arg wt "$worktree_path" \
    --arg orig "$original_path" \
    --arg issue "$issue_num" \
    --arg ts "$created" \
    '{worktree_path: $wt, original_path: $orig, issue: $issue, created: $ts}' \
    > "$state_file"
  echo "Worktree state saved: ${worktree_path}"
}

get_state() {
  local state_file=""
  repository_state_file >/dev/null 2>&1 && state_file=$(repository_state_file)
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    cat "$state_file"
  elif [ -f "$LEGACY_STATE_FILE" ]; then
    cat "$LEGACY_STATE_FILE"
  else
    echo "{}"
  fi
}

clear_state() {
  local cleared=false state_file=""
  repository_state_file >/dev/null 2>&1 && state_file=$(repository_state_file)
  if [ -n "$state_file" ] && [ -f "$state_file" ]; then
    rm -f "$state_file"
    cleared=true
  fi
  if [ -f "$LEGACY_STATE_FILE" ]; then
    rm -f "$LEGACY_STATE_FILE"
    cleared=true
  fi
  if [ "$cleared" = true ]; then
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
