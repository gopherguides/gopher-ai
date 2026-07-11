#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PLANNER="$ROOT_DIR/plugins/go-workflow/scripts/review-plan.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-review-plan-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing: $2)" ;; esac; }

new_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name "Review Planner Test"
  printf 'baseline\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm baseline
}

run_plan() {
  local repo="$1"
  shift
  (cd "$repo" && "$PLANNER" --base HEAD^ "$@")
}

echo "=== Adaptive Review Planner Tests ==="

repo="$TEST_ROOT/small"
new_repo "$repo"
mkdir -p "$repo/internal/service"
printf 'package service\n\nfunc Ready() bool { return true }\n' > "$repo/internal/service/service.go"
git -C "$repo" add .
git -C "$repo" commit -qm semantic
output=$(run_plan "$repo" --backend codex --scope "error handling")
assert_contains "$output" "actual changes: +3 -0 across 1 files" "small semantic stats"
assert_contains "$output" "semantic=1" "small semantic classification"
assert_contains "$output" "mode: full-context" "small semantic plan"
assert_contains "$output" "explicit focus: error handling" "scope with spaces"
echo "  small semantic diff: OK"

repo="$TEST_ROOT/large"
new_repo "$repo"
index=0
for area in api auth billing cli data docs worker; do
  mkdir -p "$repo/$area/component"
  for file_number in $(seq 1 12); do
    index=$((index + 1))
    awk -v area="$area" -v idx="$index" 'BEGIN { print "package component"; for (i = 1; i <= 100; i++) print "var " area idx "Value" i " = " i }' > "$repo/$area/component/change-$file_number.go"
  done
done
git -C "$repo" add .
git -C "$repo" commit -qm large
output=$(run_plan "$repo" --backend codex)
assert_contains "$output" "mode: partitioned" "large multi-area plan"
assert_contains "$output" "unit 1:" "large multi-area units"
assert_contains "$output" "final pass: cross-cutting interfaces" "large multi-area coordinator"
assert_contains "$output" "REVIEW_PLAN_REQUIRES_INPUT=no" "large review remains autonomous"
echo "  large multi-area diff: OK"

repo="$TEST_ROOT/generated"
new_repo "$repo"
mkdir -p "$repo/generated" "$repo/internal/source"
awk 'BEGIN { for (i = 1; i <= 4000; i++) print "generated line " i }' > "$repo/generated/schema.gen.json"
printf 'package source\n\nconst Version = 2\n' > "$repo/internal/source/source.go"
git -C "$repo" add .
git -C "$repo" commit -qm generated
output=$(run_plan "$repo" --backend codex)
assert_contains "$output" "generated=1" "generated-heavy classification"
assert_contains "$output" "generated integrity verification" "generated-heavy coverage"
assert_contains "$output" "mode: full-context" "generated volume discounted"
echo "  generated-heavy diff: OK"

repo="$TEST_ROOT/deletion"
new_repo "$repo"
mkdir -p "$repo/internal/old"
awk 'BEGIN { print "package old"; for (i = 1; i <= 500; i++) print "var Old" i " = " i }' > "$repo/internal/old/old.go"
git -C "$repo" add .
git -C "$repo" commit -qm add-old
rm "$repo/internal/old/old.go"
git -C "$repo" add -u
git -C "$repo" commit -qm delete-old
output=$(run_plan "$repo" --backend codex)
assert_contains "$output" "deletion-only=1" "deletion-heavy classification"
assert_contains "$output" "old.go [deletion-only]" "deletion-heavy assignment"
echo "  deletion-heavy diff: OK"

output=$(run_plan "$TEST_ROOT/large" --backend ollama --concurrency no)
assert_contains "$output" "concurrent=no" "non-concurrent backend capability"
assert_contains "$output" "execute units sequential" "non-concurrent execution plan"
echo "  backend without concurrent agents: OK"

echo "All adaptive review planner tests passed."
