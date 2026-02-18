#!/bin/bash
# PreToolUse validation hook for go-workflow
# Validates environment, tool availability, and git state before tool execution.
#
# Hook input (stdin): JSON with tool_name, tool_input fields
# Exit 0 with no output: allow tool use
# Exit 0 with JSON {"decision":"block","reason":"..."}: block tool use

set -euo pipefail

HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // empty' 2>/dev/null)

check_env_vars() {
  local missing=()
  case "$TOOL_NAME" in
    mcp__gopher-guides__*)
      [ -z "${GOPHER_GUIDES_API_KEY:-}" ] && missing+=("GOPHER_GUIDES_API_KEY")
      ;;
    *)
      [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ] && {
        if echo "$TOOL_INPUT" | grep -qiE 'github|gh |pull.request|issue' 2>/dev/null; then
          missing+=("GITHUB_TOKEN")
        fi
      }
      [ -z "${OPENAI_API_KEY:-}" ] && {
        if echo "$TOOL_INPUT" | grep -qiE 'openai|gpt|codex' 2>/dev/null; then
          missing+=("OPENAI_API_KEY")
        fi
      }
      ;;
  esac
  if [ ${#missing[@]} -gt 0 ]; then
    echo "Warning: Missing environment variables: ${missing[*]}" >&2
  fi
}

check_tool_availability() {
  local cmd_text
  cmd_text=$(echo "$TOOL_INPUT" | jq -r '.command // .cmd // empty' 2>/dev/null)
  [ -z "$cmd_text" ] && return 0
  case "$TOOL_NAME" in
    Bash|bash)
      if echo "$cmd_text" | grep -q 'golangci-lint' && ! command -v golangci-lint &>/dev/null; then
        # Allow go install commands for the tool itself
        if ! echo "$cmd_text" | grep -qE 'go install.*golangci-lint'; then
          printf '{"decision":"block","reason":"golangci-lint is not installed. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"}\n'
          exit 0
        fi
      fi
      if echo "$cmd_text" | grep -q 'templ ' && ! command -v templ &>/dev/null; then
        # Allow go install commands for the tool itself
        if ! echo "$cmd_text" | grep -qE 'go install.*templ'; then
          printf '{"decision":"block","reason":"templ is not installed. Install with: go install github.com/a-h/templ/cmd/templ@latest"}\n'
          exit 0
        fi
      fi
      if echo "$cmd_text" | grep -qE '^gh |[|&;] *gh ' && ! command -v gh &>/dev/null; then
        printf '{"decision":"block","reason":"GitHub CLI (gh) is not installed. Install from https://cli.github.com/"}\n'
        exit 0
      fi
      if echo "$cmd_text" | grep -qE '^node |[|&;] *node |npx |npm ' && ! command -v node &>/dev/null; then
        printf '{"decision":"block","reason":"Node.js is not installed. Install from https://nodejs.org/"}\n'
        exit 0
      fi
      ;;
  esac
}

check_git_state() {
  git rev-parse --is-inside-work-tree &>/dev/null || return 0
  local cmd_text
  cmd_text=$(echo "$TOOL_INPUT" | jq -r '.command // .cmd // empty' 2>/dev/null)
  [ -z "$cmd_text" ] && return 0
  if echo "$cmd_text" | grep -qE 'go test|golangci-lint run'; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      echo "Warning: Uncommitted changes detected. Test results may not reflect saved code." >&2
    fi
  fi
  if echo "$cmd_text" | grep -qE 'git tag|goreleaser|/release'; then
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      printf '{"decision":"block","reason":"Uncommitted changes detected. Please commit or stash changes before releasing."}\n'
      exit 0
    fi
  fi
}

check_worktree_path() {
  local state_file="${HOME}/.claude/worktree-state.json"
  [ -f "$state_file" ] || return 0

  local worktree_path original_path target_path=""
  worktree_path=$(jq -r '.worktree_path // empty' "$state_file" 2>/dev/null)
  original_path=$(jq -r '.original_path // empty' "$state_file" 2>/dev/null)
  [ -z "$worktree_path" ] || [ -z "$original_path" ] && return 0

  # Only enforce if current repo matches the saved original_path or worktree_path
  # original_path is now always the repo root (from git rev-parse --show-toplevel)
  local current_repo
  current_repo=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  [ "$current_repo" != "$original_path" ] && [ "$current_repo" != "$worktree_path" ] && return 0

  case "$TOOL_NAME" in
    Read|Edit|Write)
      target_path=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
      ;;
    Glob|Grep)
      target_path=$(echo "$TOOL_INPUT" | jq -r '.path // empty' 2>/dev/null)
      ;;
    Bash|bash)
      local cmd_text
      cmd_text=$(echo "$TOOL_INPUT" | jq -r '.command // .cmd // empty' 2>/dev/null)
      [ -z "$cmd_text" ] && return 0
      # Always allow worktree-state.sh commands (even with || true for cleanup)
      if echo "$cmd_text" | grep -qF "worktree-state.sh" 2>/dev/null; then
        return 0
      fi
      # Whitelist: simple (non-compound) git/gh management commands
      # remove-worktree and prune-worktree clear state at prompt assembly time,
      # so they won't be affected by this restriction
      if ! echo "$cmd_text" | grep -qE '&&|\|\||;' 2>/dev/null; then
        if echo "$cmd_text" | grep -qE "^(git (worktree|branch|fetch|remote|status|rev-parse|log)|gh (pr|issue|api)|echo |basename )" 2>/dev/null; then
          return 0
        fi
      fi
      # Block commands that explicitly reference the original repo
      if echo "$cmd_text" | grep -qF "$original_path" 2>/dev/null; then
        if ! echo "$cmd_text" | grep -qF "$worktree_path" 2>/dev/null; then
          printf '{"decision":"block","reason":"WRONG DIRECTORY: Your Bash command references the original repo (%s) instead of the worktree (%s). Replace the path to use the worktree."}\n' "$original_path" "$worktree_path"
          exit 0
        fi
      fi
      # Require commands to cd into the exact worktree path
      # Uses case pattern matching (not regex) to avoid metacharacter issues in paths
      local cd_ok=false
      case "$cmd_text" in
        "cd ${worktree_path} &&"*) cd_ok=true ;;
        "cd ${worktree_path}") cd_ok=true ;;
        "cd \"${worktree_path}\" &&"*) cd_ok=true ;;
        "cd \"${worktree_path}\"") cd_ok=true ;;
        "cd '${worktree_path}' &&"*) cd_ok=true ;;
        "cd '${worktree_path}'") cd_ok=true ;;
      esac
      if [ "$cd_ok" = false ]; then
        printf '{"decision":"block","reason":"WRONG DIRECTORY: Your Bash command must start with cd into the worktree. Prefix with: cd %s && "}\n' "$worktree_path"
        exit 0
      fi
      return 0
      ;;
    *)
      return 0
      ;;
  esac

  [ -z "$target_path" ] && return 0

  # Block relative paths — they resolve to the original repo CWD after plan mode reset
  case "$target_path" in
    /*)
      # Absolute path — allow worktree, block original repo
      # original_path is always the repo root (git rev-parse --show-toplevel)
      case "$target_path" in
        "${worktree_path}"|"${worktree_path}"/*)
          return 0
          ;;
        "${original_path}"|"${original_path}"/*)
          printf '{"decision":"block","reason":"WRONG DIRECTORY: You are targeting the original repo (%s) instead of the worktree (%s). Use path: %s%s"}\n' \
            "$original_path" "$worktree_path" "$worktree_path" "${target_path#"$original_path"}"
          exit 0
          ;;
      esac
      ;;
    *)
      # Relative path — block with guidance to use absolute worktree path
      printf '{"decision":"block","reason":"WRONG DIRECTORY: Relative path \"%s\" resolves to the original repo CWD, not the worktree. Use absolute path: %s/%s"}\n' \
        "$target_path" "$worktree_path" "$target_path"
      exit 0
      ;;
  esac
}

check_env_vars
check_tool_availability
check_git_state
check_worktree_path
exit 0
