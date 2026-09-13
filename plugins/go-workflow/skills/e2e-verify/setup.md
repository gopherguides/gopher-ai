# E2E Verify — Setup

Loaded by `SKILL.md` during setup. Read and execute every section before loop initialization.

## Parse Arguments

Extract PR number and mode from `SKILL_ARGS`:

```bash
MODE="verify"
PR_ARG=""
for arg in $SKILL_ARGS; do
  case "$arg" in
    verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship) MODE="$arg" ;;
    *) if echo "$arg" | grep -qE '^[0-9]+$'; then PR_ARG="$arg"; fi ;;
  esac
done
echo "MODE=$MODE PR_ARG=$PR_ARG"
```

## Resolve PR Number

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
WORKTREE_PATH="${WORKTREE_PATH:-$CURRENT_CHECKOUT_ROOT}"
if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] ||
   [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
  echo "ERROR: Could not resolve absolute repository paths."
  exit 1
fi
CURRENT_REPO_SLUG=$(cd "$WORKTREE_PATH" && gh api "repos/{owner}/{repo}" --jq '.full_name')
REPO_SLUG="${REPO_SLUG:-$CURRENT_REPO_SLUG}"
PR_JSON=""
if [ -n "$PR_ARG" ]; then
  PR_NUM="$PR_ARG"
  if ! PR_JSON=$(cd "$WORKTREE_PATH" && github_pr "$PR_NUM" 2>/dev/null); then
    echo "Error: PR #$PR_NUM does not exist"
    exit 1
  fi
elif PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null); then
  PR_NUM=$(jq -er '.number' <<< "$PR_JSON")
else
  PR_NUM=""
fi

if [ -z "$PR_NUM" ]; then
  echo "Claude Code: /go-workflow:e2e-verify [PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
  echo "Codex: \$go-workflow:e2e-verify [PR-number] [verify|fix-and-verify|investigate|ship-prep|ship|fix-and-ship]"
else
  echo "Working on PR #$PR_NUM in mode: $MODE"
fi
```

If `PR_NUM` is empty, this is a **missing-intent gate**. Request the PR number
through native structured input when available; otherwise ask in the final
response and stop before loop initialization or a completion claim.
