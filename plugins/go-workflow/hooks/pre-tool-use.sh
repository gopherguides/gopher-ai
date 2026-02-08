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
        printf '{"decision":"block","reason":"golangci-lint is not installed. Install with: go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"}\n'
        exit 0
      fi
      if echo "$cmd_text" | grep -q 'templ ' && ! command -v templ &>/dev/null; then
        printf '{"decision":"block","reason":"templ is not installed. Install with: go install github.com/a-h/templ/cmd/templ@latest"}\n'
        exit 0
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

check_env_vars
check_tool_availability
check_git_state
exit 0
