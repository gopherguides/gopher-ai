#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ACTIONS_SCRIPT="$ROOT_DIR/plugins/go-workflow/scripts/review-deep-post-fix.sh"
SKILL_FILE="$ROOT_DIR/plugins/go-workflow/skills/review-deep/SKILL.md"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/review-deep-actions-XXXXXX")"
REMOTE_REPO="$FIXTURE_ROOT/remote.git"
WORK_REPO="$FIXTURE_ROOT/work"
ERRORS=0

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

file_contains() {
  local needle="$1"
  local file="$2"

  awk -v needle="$needle" 'index($0, needle) { found = 1 } END { exit found ? 0 : 1 }' "$file"
}

require_skill_text() {
  local needle="$1"
  local label="$2"

  if ! file_contains "$needle" "$SKILL_FILE"; then
    fail "$label"
  fi
}

git init -q --bare "$REMOTE_REPO"
git init -q -b review "$WORK_REPO"
git -C "$WORK_REPO" config user.name "Test User"
git -C "$WORK_REPO" config user.email "test@example.com"
printf '%s\n' "base" > "$WORK_REPO/tracked.txt"
git -C "$WORK_REPO" add tracked.txt
git -C "$WORK_REPO" commit -q -m "test: initialize fixture"
git -C "$WORK_REPO" remote add origin "$REMOTE_REPO"
git -C "$WORK_REPO" push -q -u origin HEAD:review

printf '%s\n' "pushed fix" >> "$WORK_REPO/tracked.txt"
PUSH_RESULT=$(
  cd "$WORK_REPO"
  bash "$ACTIONS_SCRIPT" \
    --commit \
    --auto-push \
    --pr-number 42 \
    --remote origin \
    --branch review \
    --message "fix: push review fix" \
    -- tracked.txt
)
LOCAL_PUSHED=$(git -C "$WORK_REPO" rev-parse HEAD)
REMOTE_PUSHED=$(git --git-dir="$REMOTE_REPO" rev-parse refs/heads/review)

if [ "$LOCAL_PUSHED" != "$REMOTE_PUSHED" ]; then
  fail "push-enabled run left the remote behind local HEAD"
fi
if ! jq -e \
  --arg remote_head "$REMOTE_PUSHED" \
  '.commit == "created" and .push == "pushed" and .remote_head == $remote_head' \
  <<<"$PUSH_RESULT" >/dev/null; then
  fail "push-enabled run did not return the pushed remote state"
fi

printf '%s\n' "local-only fix" >> "$WORK_REPO/tracked.txt"
NO_PUSH_RESULT=$(
  cd "$WORK_REPO"
  bash "$ACTIONS_SCRIPT" \
    --commit \
    --no-push \
    --remote origin \
    --branch review \
    --message "fix: keep review fix local" \
    -- tracked.txt
)
LOCAL_UNPUSHED=$(git -C "$WORK_REPO" rev-parse HEAD)
REMOTE_UNPUSHED=$(git --git-dir="$REMOTE_REPO" rev-parse refs/heads/review)

if [ "$LOCAL_UNPUSHED" = "$REMOTE_UNPUSHED" ]; then
  fail "push-disabled run unexpectedly changed the remote"
fi
if [ "$REMOTE_UNPUSHED" != "$REMOTE_PUSHED" ]; then
  fail "push-disabled run did not preserve the prior remote head"
fi
if ! jq -e \
  --arg remote_head "$REMOTE_UNPUSHED" \
  '.commit == "created" and .push == "skipped" and .remote_head == $remote_head' \
  <<<"$NO_PUSH_RESULT" >/dev/null; then
  fail "push-disabled run did not return the local-only remote state"
fi

printf '%s\n' "uncommitted fix" >> "$WORK_REPO/tracked.txt"
NO_COMMIT_HEAD=$(git -C "$WORK_REPO" rev-parse HEAD)
NO_COMMIT_RESULT=$(
  cd "$WORK_REPO"
  bash "$ACTIONS_SCRIPT" \
    --no-commit \
    --no-push \
    --remote origin \
    --branch review \
    -- tracked.txt
)

if [ "$(git -C "$WORK_REPO" rev-parse HEAD)" != "$NO_COMMIT_HEAD" ]; then
  fail "commit-disabled run created a commit"
fi
if git -C "$WORK_REPO" diff --quiet -- tracked.txt; then
  fail "commit-disabled run did not preserve the working-tree fix"
fi
if ! jq -e \
  '.commit == "skipped" and .push == "skipped"' \
  <<<"$NO_COMMIT_RESULT" >/dev/null; then
  fail "commit-disabled run did not report skipped actions"
fi

set +e
BLOCKED_PUSH_RESULT=$(
  cd "$WORK_REPO"
  bash "$ACTIONS_SCRIPT" \
    --no-commit \
    --push \
    --remote origin \
    --branch review \
    -- tracked.txt 2>&1
)
BLOCKED_PUSH_STATUS=$?
set -e

if [ "$BLOCKED_PUSH_STATUS" -eq 0 ]; then
  fail "push proceeded while review-owned fixes were uncommitted"
fi
if [[ "$BLOCKED_PUSH_RESULT" != *"cannot push review-owned changes before committing them"* ]]; then
  fail "blocked push did not explain the commit dependency"
fi
if [ "$(git --git-dir="$REMOTE_REPO" rev-parse refs/heads/review)" != "$REMOTE_UNPUSHED" ]; then
  fail "blocked push changed the remote"
fi

require_skill_text '--no-fix' "review fixes are not independently controllable"
require_skill_text '--no-commit' "review commits are not independently controllable"
require_skill_text '--push' "review pushes cannot be explicitly enabled"
require_skill_text '--no-push' "review pushes cannot be explicitly disabled"
require_skill_text 'PR-backed runs push newly created review commits by default' \
  "default PR push ownership is not documented"
if ! file_contains '--auto-push --pr-number' \
  "$ROOT_DIR/plugins/go-workflow/skills/review-deep/fix-and-verify.md"; then
  fail "default PR push behavior does not route through the tested helper mode"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS review-deep action issue(s)"
  exit 1
fi

echo "All review-deep action tests passed."
