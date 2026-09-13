# Address-Review Entry and PR Resolution

Loaded by `skills/address-review/SKILL.md` during entry setup. Execute the complete procedure before loop initialization or feedback discovery.

## Output Durability

Replies to review comments and any new commit messages describe what behavior changed and why, not file paths or line numbers. A reviewer reading the reply six months later, after the file in question has moved, must still understand what was fixed.

**If `SKILL_ARGS` is empty or not provided:**

Auto-detect PR from current branch:

```bash
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_PATH="$CURRENT_CHECKOUT_ROOT"
CURRENT_PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null) || true
jq -r '.number' <<< "$CURRENT_PR_JSON" 2>/dev/null
```

If no PR is found, display usage:

**Claude Code:** `/go-workflow:address-review [PR-number] [--no-watch]`

**Codex:** `$go-workflow:address-review [PR-number] [--no-watch]`

**Example:** `/address-review 123` or just `/address-review` on a PR branch. Add `--no-watch` to exit after one fix cycle instead of watching for bot re-reviews.

This is a **missing-intent gate**. Request: "No PR was found for the current
branch. What PR number should I address?" If structured input is unavailable,
ask in the final response and stop before loop initialization or a completion
claim.

---

**If PR number is available (from `SKILL_ARGS` or auto-detected):**

## Parse Arguments

```bash
WATCH_MODE=true
PR_ARG=""
for arg in $SKILL_ARGS; do
  case "$arg" in
    --no-watch) WATCH_MODE=false ;;
    *) PR_ARG="$arg" ;;
  esac
done
echo "WATCH_MODE=$WATCH_MODE PR_ARG=$PR_ARG"
```

## Security Validation

!if [ -n "$PR_ARG" ] && ! echo "$PR_ARG" | grep -qE '^[0-9]+$'; then echo "Error: PR number must be numeric"; exit 1; fi

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
if [ -n "$PR_ARG" ]; then
  RESOLVED_PR="$PR_ARG"
elif CURRENT_PR_JSON=$(cd "$WORKTREE_PATH" && github_current_pr 2>/dev/null); then
  RESOLVED_PR=$(jq -er '.number' <<< "$CURRENT_PR_JSON")
else
  RESOLVED_PR="auto"
fi
PR_NUM="$RESOLVED_PR"
echo "Resolved PR: $RESOLVED_PR"
```
