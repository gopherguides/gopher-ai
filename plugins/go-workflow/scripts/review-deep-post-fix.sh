#!/usr/bin/env bash
set -euo pipefail

DO_COMMIT=true
PUSH_MODE=false
PR_NUMBER=""
PUSH_REMOTE=""
PUSH_BRANCH=""
COMMIT_MESSAGE=""
OWNED_FILES=()

usage() {
  echo "usage: review-deep-post-fix.sh [--commit|--no-commit] [--auto-push|--push|--no-push] [--pr-number <number>] [--remote <name>] [--branch <name>] [--message <text>] [-- <owned-files...>]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --commit)
      DO_COMMIT=true
      shift
      ;;
    --no-commit)
      DO_COMMIT=false
      shift
      ;;
    --auto-push)
      PUSH_MODE=auto
      shift
      ;;
    --push)
      PUSH_MODE=true
      shift
      ;;
    --no-push)
      PUSH_MODE=false
      shift
      ;;
    --pr-number)
      [ "$#" -ge 2 ] || usage
      PR_NUMBER="$2"
      shift 2
      ;;
    --remote)
      [ "$#" -ge 2 ] || usage
      PUSH_REMOTE="$2"
      shift 2
      ;;
    --branch)
      [ "$#" -ge 2 ] || usage
      PUSH_BRANCH="$2"
      shift 2
      ;;
    --message)
      [ "$#" -ge 2 ] || usage
      COMMIT_MESSAGE="$2"
      shift 2
      ;;
    --)
      shift
      OWNED_FILES=("$@")
      break
      ;;
    *)
      usage
      ;;
  esac
done

git rev-parse --show-toplevel >/dev/null

COMMIT_RESULT="skipped"
if [ "$DO_COMMIT" = true ]; then
  if ! git diff --cached --quiet; then
    echo "Error: pre-existing staged changes must be committed or unstaged before review-deep can commit." >&2
    exit 1
  fi

  if [ "${#OWNED_FILES[@]}" -gt 0 ]; then
    git add -- "${OWNED_FILES[@]}"
  fi

  if git diff --cached --quiet; then
    COMMIT_RESULT="none"
  else
    if [ -z "$COMMIT_MESSAGE" ]; then
      echo "Error: --message is required when review-deep has changes to commit." >&2
      exit 1
    fi
    git commit -m "$COMMIT_MESSAGE" >&2
    COMMIT_RESULT="created"
  fi
fi

DO_PUSH=false
case "$PUSH_MODE" in
  true)
    DO_PUSH=true
    ;;
  false)
    DO_PUSH=false
    ;;
  auto)
    if [ -n "$PR_NUMBER" ] && [ "$COMMIT_RESULT" = "created" ]; then
      DO_PUSH=true
    fi
    ;;
  *)
    usage
    ;;
esac

if [ "$DO_PUSH" = true ] && [ "$DO_COMMIT" = false ] && [ "${#OWNED_FILES[@]}" -gt 0 ]; then
  if [ -n "$(git status --porcelain -- "${OWNED_FILES[@]}")" ]; then
    echo "Error: cannot push review-owned changes before committing them." >&2
    exit 1
  fi
fi

if [ "$DO_PUSH" = true ]; then
  if [ -z "$PUSH_REMOTE" ] || [ -z "$PUSH_BRANCH" ]; then
    echo "Error: --remote and --branch are required when push is enabled." >&2
    exit 1
  fi
  git push -u "$PUSH_REMOTE" "HEAD:$PUSH_BRANCH" >&2
fi

LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=""
if [ -n "$PUSH_REMOTE" ] && [ -n "$PUSH_BRANCH" ]; then
  if [ "$DO_PUSH" = true ]; then
    REMOTE_HEAD=$(git ls-remote --heads "$PUSH_REMOTE" "refs/heads/$PUSH_BRANCH" | awk 'NR == 1 {print $1}')
  else
    REMOTE_HEAD=$(git ls-remote --heads "$PUSH_REMOTE" "refs/heads/$PUSH_BRANCH" 2>/dev/null | awk 'NR == 1 {print $1}' || true)
  fi
fi

PUSH_RESULT="skipped"
if [ "$DO_PUSH" = true ]; then
  if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    echo "Error: remote head does not match the committed review result." >&2
    exit 1
  fi
  PUSH_RESULT="pushed"
fi

printf '{"commit":"%s","push":"%s","local_head":"%s","remote_head":"%s"}\n' \
  "$COMMIT_RESULT" "$PUSH_RESULT" "$LOCAL_HEAD" "$REMOTE_HEAD"
