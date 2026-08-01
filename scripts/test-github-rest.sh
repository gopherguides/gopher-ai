#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REST_LIB="$ROOT_DIR/plugins/go-workflow/lib/github-rest.sh"
ERRORS=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  ERRORS=$((ERRORS + 1))
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$actual" != "$expected" ]; then
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_status() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if [ "$actual" -ne "$expected" ]; then
    fail "$label (expected status $expected, got $actual)"
  fi
}

printf '=== GitHub REST Helper Tests ===\n'

if [ ! -f "$REST_LIB" ]; then
  fail "shared GitHub REST helper is missing"
  printf 'FAILED: %s GitHub REST helper issue(s)\n' "$ERRORS"
  exit 1
fi

source "$REST_LIB"

current_pr=$(
  gh() {
    if [ "$1" = "api" ] && [[ "$*" == *"commits/head-sha/pulls"* ]]; then
      printf '%s\n' '[[{"number":41,"state":"open","head":{"ref":"feature","sha":"head-sha"}},{"number":42,"state":"closed","head":{"ref":"feature","sha":"head-sha"}}]]'
      return 0
    fi
    return 1
  }
  git() {
    if [ "$*" = "branch --show-current" ]; then
      printf '%s\n' "feature"
    elif [ "$*" = "rev-parse HEAD" ]; then
      printf '%s\n' "head-sha"
    else
      return 1
    fi
  }
  github_current_pr
)
assert_equal "41" "$(printf '%s' "$current_pr" | jq -r '.number')" "current PR lookup selects the open exact-head PR"

metadata=$(
  gh() {
    if [ "$1" = "api" ] && [[ "$*" == *"pulls/41"* ]]; then
      printf '%s\n' '{"number":41,"title":"REST","head":{"sha":"head-sha"}}'
      return 0
    fi
    return 1
  }
  github_pr 41
)
assert_equal "REST" "$(printf '%s' "$metadata" | jq -r '.title')" "PR metadata uses the REST pull endpoint"

reviews=$(
  gh() {
    if [ "$1" = "api" ] && [[ "$*" == *"pulls/41/reviews"* ]]; then
      printf '%s\n' '[[{"id":1,"state":"COMMENTED"}],[{"id":2,"state":"APPROVED"}]]'
      return 0
    fi
    return 1
  }
  github_pr_reviews 41
)
assert_equal "2" "$(printf '%s' "$reviews" | jq 'length')" "formal review pagination is flattened"

check_only=$(
  gh() {
    if [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[{"id":1,"name":"build","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  github_check_snapshot "head-sha"
)
assert_equal "check-run" "$(printf '%s' "$check_only" | jq -r '.items[0].kind')" "check-run snapshots are normalized"
assert_equal "true" "$(printf '%s' "$check_only" | jq -r '.items[0].successful')" "successful check-runs are terminal successes"

rerun=$(
  gh() {
    if [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[{"id":1,"name":"build","status":"completed","conclusion":"failure","app":{"slug":"actions"}},{"id":2,"name":"build","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  github_check_snapshot "head-sha"
)
assert_equal "1" "$(printf '%s' "$rerun" | jq '.items | length')" "rerun snapshots retain only the latest check identity"
assert_equal "2" "$(printf '%s' "$rerun" | jq -r '.items[0].source_id')" "rerun snapshots retain the newest check run"

status_only=$(
  gh() {
    if [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[{"id":7,"context":"legacy","state":"success"}]}'
    else
      return 1
    fi
  }
  github_check_snapshot "head-sha"
)
assert_equal "status" "$(printf '%s' "$status_only" | jq -r '.items[0].kind')" "combined commit statuses are normalized"

mixed=$(
  gh() {
    if [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[{"id":1,"name":"build","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[{"id":7,"context":"legacy","state":"pending"}]}'
    else
      return 1
    fi
  }
  github_check_snapshot "head-sha"
)
assert_equal "2" "$(printf '%s' "$mixed" | jq '.items | length')" "mixed check sources are aggregated"
assert_equal "1" "$(printf '%s' "$mixed" | jq '[.items[] | select(.terminal == false)] | length')" "pending statuses remain non-terminal"

set +e
failure_output=$(
  gh() {
    if [[ "$*" == *"pulls/41"* ]]; then
      printf '%s\n' '{"number":41,"head":{"sha":"head-sha"}}'
    elif [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[{"id":1,"name":"unit","status":"completed","conclusion":"failure","app":{"slug":"actions"}},{"id":2,"name":"lint","status":"completed","conclusion":"timed_out","app":{"slug":"actions"}}]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  sleep() { :; }
  GITHUB_CHECK_STABILITY_POLLS=1 github_watch_pr_checks 41 "head-sha"
)
failure_status=$?
set -e
assert_status "$GITHUB_CHECKS_FAILED" "$failure_status" "terminal check failures use the failure status"
assert_equal "2" "$(printf '%s' "$failure_output" | jq '[.items[] | select(.terminal and (.successful | not))] | length')" "all terminal failures are reported together"

late_state=$(mktemp "${TMPDIR:-/tmp}/github-rest-late-XXXXXX")
printf '0\n' > "$late_state"
set +e
late_output=$(
  gh() {
    if [[ "$*" == *"pulls/41"* ]]; then
      printf '%s\n' '{"number":41,"head":{"sha":"head-sha"}}'
    elif [[ "$*" == *"check-runs"* ]]; then
      local count
      count=$(cat "$late_state")
      count=$((count + 1))
      printf '%s\n' "$count" > "$late_state"
      if [ "$count" -eq 1 ]; then
        printf '%s\n' '[{"check_runs":[{"id":1,"name":"unit","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
      elif [ "$count" -eq 2 ]; then
        printf '%s\n' '[{"check_runs":[{"id":1,"name":"unit","status":"completed","conclusion":"success","app":{"slug":"actions"}},{"id":2,"name":"late","status":"in_progress","conclusion":null,"app":{"slug":"actions"}}]}]'
      else
        printf '%s\n' '[{"check_runs":[{"id":1,"name":"unit","status":"completed","conclusion":"success","app":{"slug":"actions"}},{"id":2,"name":"late","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
      fi
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  sleep() { :; }
  GITHUB_CHECK_STABILITY_POLLS=2 github_watch_pr_checks 41 "head-sha"
)
late_status=$?
set -e
late_polls=$(cat "$late_state")
rm -f "$late_state"
assert_status 0 "$late_status" "late check registration still reaches success"
assert_equal "2" "$(printf '%s' "$late_output" | jq '.items | length')" "late registered checks appear in the final snapshot"
if [ "$late_polls" -lt 4 ]; then
  fail "late registration must reset the stability window"
fi

set +e
timeout_output=$(
  gh() {
    if [[ "$*" == *"pulls/41"* ]]; then
      printf '%s\n' '{"number":41,"head":{"sha":"head-sha"}}'
    elif [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  sleep() { :; }
  GITHUB_CHECK_REGISTRATION_ATTEMPTS=2 github_watch_pr_checks 41 "head-sha"
)
timeout_status=$?
set -e
assert_status "$GITHUB_CHECKS_REGISTRATION_TIMEOUT" "$timeout_status" "missing registration has a distinct bounded-timeout status"
assert_equal "" "$timeout_output" "registration timeout does not emit a passing snapshot"

set +e
api_output=$(
  gh() {
    if [[ "$*" == *"pulls/41"* ]]; then
      printf '%s\n' '{"number":41,"head":{"sha":"head-sha"}}'
      return 0
    fi
    return 1
  }
  sleep() { :; }
  github_watch_pr_checks 41 "head-sha"
)
api_status=$?
set -e
assert_status "$GITHUB_CHECKS_API_ERROR" "$api_status" "REST failures have a distinct status"
assert_equal "" "$api_output" "API failure does not emit a passing snapshot"

head_reads=$(mktemp "${TMPDIR:-/tmp}/github-rest-head-XXXXXX")
printf '0\n' > "$head_reads"
set +e
shift_output=$(
  gh() {
    if [[ "$*" == *"pulls/41"* ]]; then
      local count
      count=$(cat "$head_reads")
      count=$((count + 1))
      printf '%s\n' "$count" > "$head_reads"
      if [ "$count" -eq 1 ]; then
        printf '%s\n' '{"number":41,"head":{"sha":"head-sha"}}'
      else
        printf '%s\n' '{"number":41,"head":{"sha":"new-sha"}}'
      fi
    elif [[ "$*" == *"check-runs"* ]]; then
      printf '%s\n' '[{"check_runs":[{"id":1,"name":"unit","status":"completed","conclusion":"success","app":{"slug":"actions"}}]}]'
    elif [[ "$*" == *"/status"* ]]; then
      printf '%s\n' '{"statuses":[]}'
    else
      return 1
    fi
  }
  sleep() { :; }
  GITHUB_CHECK_STABILITY_POLLS=1 github_watch_pr_checks 41 "head-sha"
)
shift_status=$?
set -e
rm -f "$head_reads"
assert_status "$GITHUB_CHECKS_HEAD_SHIFT" "$shift_status" "post-watch PR head shift has a distinct status"
assert_equal "" "$shift_output" "head shift does not emit a passing snapshot"

WORKFLOW_PATHS=(
  "$ROOT_DIR/plugins/go-workflow/skills/ship"
  "$ROOT_DIR/plugins/go-workflow/lib/ship"
  "$ROOT_DIR/plugins/go-workflow/skills/address-review"
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify"
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue"
)
WORKFLOW_FILES=()
while IFS= read -r workflow_file; do
  WORKFLOW_FILES+=("$workflow_file")
done < <(find "${WORKFLOW_PATHS[@]}" -type f -name '*.md' -print)

checks_calls=$(grep -nF 'gh pr checks' "${WORKFLOW_FILES[@]}" | grep -vE 'Avoid|Forbidden|must not|Do not' || true)
if [ -n "$checks_calls" ]; then
  fail "routine gh pr checks calls remain"
fi

replaceable_views=$(grep -nE 'gh pr view.*--json' "${WORKFLOW_FILES[@]}" | grep -vE 'closingIssuesReferences|Avoid|instead of|must not|Do not' || true)
if [ -n "$replaceable_views" ]; then
  fail "replaceable gh pr view --json calls remain"
fi

routine_cli_calls=$(grep -nE 'gh repo view --json|gh pr (checkout|edit)' "${WORKFLOW_FILES[@]}" || true)
if [ -n "$routine_cli_calls" ]; then
  fail "REST-replaceable repository or PR CLI calls remain"
fi

review_queries=$(grep -nE '(^|[[:space:]])(latestReviews|reviews)\(first:' "${WORKFLOW_FILES[@]}" || true)
if [ -n "$review_queries" ]; then
  fail "REST-replaceable GraphQL review lists remain"
fi

merge_calls=$(grep -nF 'gh pr merge' "${WORKFLOW_FILES[@]}" | grep -vE 'required merge queue|merge-queue exception' || true)
merge_command_count=$(printf '%s\n' "$merge_calls" | grep -cE 'lib/ship/merge\.md:.*gh pr merge' || true)
assert_equal "1" "$merge_command_count" "gh pr merge remains only as the queue command"
unexpected_merge_calls=$(printf '%s\n' "$merge_calls" | grep -vE 'lib/ship/merge\.md:.*gh pr merge' || true)
if [ -n "$unexpected_merge_calls" ]; then
  fail "gh pr merge remains outside the queue implementation"
fi

if ! tr '\n' ' ' < "$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md" | grep -qE 'if \[ "\$HAS_MERGE_QUEUE" = "true" \]; then[[:space:]]+gh pr merge'; then
  fail "queue-only gh pr merge is not structurally guarded"
fi
if ! grep -qF 'gh api --method PUT "repos/$REPO_SLUG/pulls/$PR_NUM/merge"' "$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"; then
  fail "ordinary merge does not use the REST pull merge endpoint"
fi
if ! grep -qF -e '-f sha="$HEAD_SHA"' "$ROOT_DIR/plugins/go-workflow/lib/ship/merge.md"; then
  fail "ordinary REST merge is not pinned to the expected head SHA"
fi

for skill_file in \
  "$ROOT_DIR/plugins/go-workflow/skills/ship/SKILL.md" \
  "$ROOT_DIR/plugins/go-workflow/skills/address-review/SKILL.md" \
  "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/SKILL.md" \
  "$ROOT_DIR/plugins/go-workflow/skills/complete-issue/SKILL.md"; do
  if ! grep -qF 'source "${CLAUDE_PLUGIN_ROOT}/lib/github-rest.sh"' "$skill_file"; then
    fail "${skill_file#"$ROOT_DIR"/} does not load the shared REST helper"
  fi
done

closing_reference_calls=$(awk '/gh pr view.*--json closingIssuesReferences/ { count++ } END { print count + 0 }' "${WORKFLOW_FILES[@]}")
assert_equal "1" "$closing_reference_calls" "closingIssuesReferences is the only gh pr view GraphQL exception"

if ! grep -qE 'reviewThreads\(first:' "${WORKFLOW_FILES[@]}"; then
  fail "GraphQL review-thread discovery was removed"
fi
if ! grep -qF 'resolveReviewThread' "${WORKFLOW_FILES[@]}"; then
  fail "GraphQL review-thread resolution was removed"
fi
if ! tr '\n' ' ' < "$ROOT_DIR/plugins/go-workflow/skills/address-review/fix-cycle.md" \
  | grep -qE 'PR_HEAD_PUSH_TARGET="".*PR_HEAD_PUSH_TARGET="\$\{PR_HEAD_PUSH_TARGET:-\$PR_HEAD_CLONE_URL\}".*git -C "\$WORKTREE_PATH" push "\$PR_HEAD_PUSH_TARGET"'; then
  fail "address-review fix cycles do not re-derive the PR head push target"
fi
if ! tr '\n' ' ' < "$ROOT_DIR/plugins/go-workflow/skills/e2e-verify/rebase-and-build.md" \
  | grep -qE 'EXPECTED_REMOTE_HEAD_SHA="\$PR_HEAD_SHA".*if \[ "\$PR_HEAD_SHA" != "\$EXPECTED_REMOTE_HEAD_SHA" \].*--force-with-lease="refs/heads/\$PR_HEAD_BRANCH:\$EXPECTED_REMOTE_HEAD_SHA".*PUBLISHED_HEAD_SHA'; then
  fail "e2e-verify rebase pushes do not preserve and verify the original PR head lease"
fi

if [ "$ERRORS" -gt 0 ]; then
  printf 'FAILED: %s GitHub REST helper issue(s)\n' "$ERRORS"
  exit 1
fi

printf 'All GitHub REST helper tests passed.\n'
