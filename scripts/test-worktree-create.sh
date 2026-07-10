#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
WORKTREE_CREATE="$ROOT_DIR/plugins/go-workflow/scripts/worktree-create.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-worktree-create.XXXXXX")
TEST_ROOT=$(cd "$TEST_ROOT" && pwd -P)
FAKE_BIN="$TEST_ROOT/bin"
ISSUE_NUMBER=42
ISSUE_TITLE="Preserve branch"
BRANCH_NAME="issue-42-preserve-branch"
ERRORS=0

trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label (expected $expected, got $actual)"
  fi
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  if [[ "$value" != *"$expected"* ]]; then
    fail "$label (missing: $expected)"
  fi
}

create_fake_gh() {
  mkdir -p "$FAKE_BIN"
  cat > "$FAKE_BIN/gh" <<'EOF'
#!/bin/bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "auth status")
    exit 0
    ;;
  "pr view")
    exit 1
    ;;
  "issue view")
    printf '{"number":%s,"title":"%s","state":"OPEN"}\n' "$3" "$GH_TEST_TITLE"
    ;;
  *)
    echo "Unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$FAKE_BIN/gh"
}

create_repo() {
  local name="$1"
  local case_root="$TEST_ROOT/$name"
  local remote="$case_root/remote.git"
  local repo="$case_root/repo"

  mkdir -p "$case_root"
  git init --bare -q "$remote"
  git -C "$remote" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$repo"
  git -C "$repo" config user.name "Worktree Test"
  git -C "$repo" config user.email "worktree-test@example.com"
  printf 'baseline\n' > "$repo/baseline.txt"
  git -C "$repo" add baseline.txt
  git -C "$repo" commit -qm "baseline"
  git -C "$repo" remote add origin "$remote"
  git -C "$repo" push -qu origin main
  printf '%s\n' "$repo"
}

target_path() {
  local repo="$1"
  printf '%s/%s-issue-%s-preserve-branch\n' "$(dirname "$repo")" "$(basename "$repo")" "$ISSUE_NUMBER"
}

run_create() {
  local repo="$1"
  PATH="$FAKE_BIN:$PATH" GH_TEST_TITLE="$ISSUE_TITLE" \
    "$WORKTREE_CREATE" create "$ISSUE_NUMBER" \
      --source-dir "$repo" \
      --no-copy-env \
      --no-register-state
}

test_existing_branch_is_preserved() {
  local repo
  repo=$(create_repo existing-branch)
  git -C "$repo" checkout -qb "$BRANCH_NAME"
  printf 'unmerged work\n' > "$repo/unmerged.txt"
  git -C "$repo" add unmerged.txt
  git -C "$repo" commit -qm "unmerged work"
  local before
  before=$(git -C "$repo" rev-parse "$BRANCH_NAME")
  git -C "$repo" checkout -q main

  run_create "$repo" >/dev/null

  local after worktree
  after=$(git -C "$repo" rev-parse "$BRANCH_NAME")
  worktree=$(target_path "$repo")
  assert_equal "$before" "$after" "existing branch ref is preserved"
  assert_equal "$before" "$(git -C "$worktree" rev-parse HEAD)" "worktree uses the existing branch commit"
  assert_equal "$BRANCH_NAME" "$(git -C "$worktree" branch --show-current)" "worktree checks out the existing branch"
}

test_fresh_branch_uses_remote_main() {
  local repo
  repo=$(create_repo fresh-branch)
  local remote_main
  remote_main=$(git -C "$repo" rev-parse origin/main)
  printf 'local only\n' > "$repo/local-only.txt"
  git -C "$repo" add local-only.txt
  git -C "$repo" commit -qm "local main work"

  run_create "$repo" >/dev/null

  local worktree
  worktree=$(target_path "$repo")
  assert_equal "$remote_main" "$(git -C "$repo" rev-parse "$BRANCH_NAME")" "fresh branch starts at remote main"
  assert_equal "$BRANCH_NAME" "$(git -C "$worktree" branch --show-current)" "fresh worktree is attached to the issue branch"
}

test_matching_worktree_is_reused() {
  local repo
  repo=$(create_repo reuse)
  run_create "$repo" >/dev/null
  local worktree before_count before_ref output
  worktree=$(target_path "$repo")
  printf 'keep me\n' > "$worktree/sentinel.txt"
  before_count=$(git -C "$repo" worktree list --porcelain | awk '/^worktree / { count++ } END { print count + 0 }')
  before_ref=$(git -C "$repo" rev-parse "$BRANCH_NAME")

  output=$(run_create "$repo")

  assert_contains "$output" "WORKTREE_EXISTS: $worktree" "matching worktree reports reuse"
  assert_equal "$before_count" "$(git -C "$repo" worktree list --porcelain | awk '/^worktree / { count++ } END { print count + 0 }')" "reuse does not add a worktree"
  assert_equal "$before_ref" "$(git -C "$repo" rev-parse "$BRANCH_NAME")" "reuse does not move the branch"
  assert_equal "keep me" "$(tr -d '\n' < "$worktree/sentinel.txt")" "reuse preserves user files"
}

test_checked_out_branch_conflict_is_non_mutating() {
  local repo
  repo=$(create_repo branch-conflict)
  local other_worktree="$TEST_ROOT/branch-conflict/other-worktree"
  git -C "$repo" worktree add -qb "$BRANCH_NAME" "$other_worktree" main
  local refs_before worktrees_before output
  refs_before=$(git -C "$repo" show-ref | sort)
  worktrees_before=$(git -C "$repo" worktree list --porcelain)

  if output=$(run_create "$repo" 2>&1); then
    fail "checked-out branch conflict succeeds unexpectedly"
    return
  fi

  assert_contains "$output" "Branch $BRANCH_NAME is checked out at $other_worktree" "checked-out branch conflict is clear"
  assert_equal "$refs_before" "$(git -C "$repo" show-ref | sort)" "checked-out branch conflict preserves refs"
  assert_equal "$worktrees_before" "$(git -C "$repo" worktree list --porcelain)" "checked-out branch conflict preserves worktrees"
  if [ -e "$(target_path "$repo")" ]; then
    fail "checked-out branch conflict creates the target path"
  fi
}

test_target_path_conflict_is_non_mutating() {
  local repo
  repo=$(create_repo path-conflict)
  local worktree
  worktree=$(target_path "$repo")
  mkdir -p "$worktree"
  printf 'keep me\n' > "$worktree/sentinel.txt"
  local refs_before worktrees_before output
  refs_before=$(git -C "$repo" show-ref | sort)
  worktrees_before=$(git -C "$repo" worktree list --porcelain)

  if output=$(run_create "$repo" 2>&1); then
    fail "target path conflict succeeds unexpectedly"
    return
  fi

  assert_contains "$output" "Target path already exists: $worktree" "target path conflict is clear"
  assert_equal "$refs_before" "$(git -C "$repo" show-ref | sort)" "target path conflict preserves refs"
  assert_equal "$worktrees_before" "$(git -C "$repo" worktree list --porcelain)" "target path conflict preserves worktrees"
  assert_equal "keep me" "$(tr -d '\n' < "$worktree/sentinel.txt")" "target path conflict preserves user files"
}

create_fake_gh

echo "=== Worktree Create Tests ==="
test_existing_branch_is_preserved
test_fresh_branch_uses_remote_main
test_matching_worktree_is_reused
test_checked_out_branch_conflict_is_non_mutating
test_target_path_conflict_is_non_mutating

if grep -qF 'branch -D' "$WORKTREE_CREATE"; then
  fail "worktree helper still contains automatic force deletion"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS worktree creation test(s) failed"
  exit 1
fi

echo "All worktree creation tests passed."
