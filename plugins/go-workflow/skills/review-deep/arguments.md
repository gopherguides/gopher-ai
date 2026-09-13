# Review-Deep Arguments and Actions

Loaded by `SKILL.md` Step 0. Execute argument parsing and preserve the independent fix, commit, push, and post semantics.

## Step 0: Parse Arguments

Parse `SKILL_ARGS` to extract:

- Bare numeric value: PR number (e.g., `$go-workflow:review-deep 42`)
- `--issue <N>`: Use specific issue as context (no PR required)
- `--post`: Auto-post findings to PR as a comment (skip asking)
- `--scope <hint>`: Focus area for the review (e.g., "error handling", "concurrency")
- `--no-fix`: Review only; do not edit files
- `--no-commit`: Apply fixes but leave review-owned changes uncommitted
- `--push`: Push the resulting local HEAD, including for a branch-only run
- `--no-push`: Never push; return the local and remote head state
- Remaining text after flags: treated as scope hint

Store as `PR_ARG`, `ISSUE_ARG`, `AUTO_POST` (default: `false`), `SCOPE_HINT`,
`FIX_CHANGES` (default: `true`), `COMMIT_CHANGES` (default: `true`), and
`PUSH_CHANGES` (default: `auto`).

```bash
PR_ARG=""
ISSUE_ARG=""
AUTO_POST=false
SCOPE_HINT=""
FIX_CHANGES=true
COMMIT_CHANGES=true
PUSH_CHANGES=auto
ARGS="$SKILL_ARGS"

while [ -n "$ARGS" ]; do
  case "$ARGS" in
    --issue\ *)
      ARGS="${ARGS#--issue }"
      ISSUE_ARG="${ARGS%% *}"
      ARGS="${ARGS#"$ISSUE_ARG"}"
      ARGS="${ARGS# }"
      ;;
    --post*)
      AUTO_POST=true
      ARGS="${ARGS#--post}"
      ARGS="${ARGS# }"
      ;;
    --scope\ *)
      ARGS="${ARGS#--scope }"
      SCOPE_HINT="$ARGS"
      ARGS=""
      ;;
    --no-fix*)
      FIX_CHANGES=false
      ARGS="${ARGS#--no-fix}"
      ARGS="${ARGS# }"
      ;;
    --no-commit*)
      COMMIT_CHANGES=false
      ARGS="${ARGS#--no-commit}"
      ARGS="${ARGS# }"
      ;;
    --no-push*)
      PUSH_CHANGES=false
      ARGS="${ARGS#--no-push}"
      ARGS="${ARGS# }"
      ;;
    --push*)
      PUSH_CHANGES=true
      ARGS="${ARGS#--push}"
      ARGS="${ARGS# }"
      ;;
    [0-9]*)
      PR_ARG="${ARGS%% *}"
      ARGS="${ARGS#"$PR_ARG"}"
      ARGS="${ARGS# }"
      ;;
    *)
      SCOPE_HINT="$ARGS"
      ARGS=""
      ;;
  esac
done

echo "PR_ARG=$PR_ARG ISSUE_ARG=$ISSUE_ARG AUTO_POST=$AUTO_POST SCOPE_HINT=$SCOPE_HINT FIX_CHANGES=$FIX_CHANGES COMMIT_CHANGES=$COMMIT_CHANGES PUSH_CHANGES=$PUSH_CHANGES"
```

### Action Contract

Fix, commit, and push are separately controllable:

| Configuration | Post-review state |
|---------------|-------------------|
| Default with a detected PR and fixes | Fix, commit, and push; local and PR remote heads must match |
| Default without a PR | Fix and commit locally; do not push |
| `--no-fix` | Review only; do not create a review commit or auto-push |
| `--no-commit` | Leave review-owned fixes in the working tree; auto-push is disabled |
| `--no-push` | Commit review-owned fixes locally and report that the remote is unchanged |
| `--push` | Push explicitly; fail if review-owned fixes are still uncommitted |

PR-backed runs push newly created review commits by default. Branch-only runs
require `--push`. Every run returns a structured commit/push result with local
and remote head SHAs; a push failure is an incomplete review, never success.
