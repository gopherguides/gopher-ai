#!/bin/bash
# Failure-injection coverage for atomic legacy hash manifest publication.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0

FIXTURE_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
case "$FIXTURE_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$FIXTURE_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac

TEST_ROOT=$(/usr/bin/mktemp -d "${FIXTURE_TMP_BASE%/}/gopher-ai-atomic-hashes.XXXXXX")
BACKGROUND_PIDS=""
cleanup() {
  local pid
  for pid in $BACKGROUND_PIDS; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM HUP

new_fixture() {
  local name="$1"
  local repo="$TEST_ROOT/$name"

  mkdir -p \
    "$repo/scripts" \
    "$repo/plugins/example/skills/example" \
    "$repo/plugins/go-workflow/hooks"
  cp "$ROOT_DIR/scripts/regen-legacy-hashes.sh" "$repo/scripts/"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name "Legacy Hash Test"
  printf '%s\n' 'base version' > "$repo/plugins/example/skills/example/SKILL.md"
  git -C "$repo" add .
  git -C "$repo" commit -qm "base"
  /bin/bash "$repo/scripts/regen-legacy-hashes.sh" --base-ref main >/dev/null
  printf '%s\n' "$repo"
}

run_with_deadline() {
  local log_file="$1"
  shift
  local pid
  local status=0
  local finished=false

  "$@" >"$log_file" 2>&1 &
  pid=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $pid"
  for _ in $(seq 1 40); do
    if ! kill -0 "$pid" 2>/dev/null; then
      finished=true
      break
    fi
    sleep 0.05
  done

  if [ "$finished" = true ]; then
    wait "$pid" || status=$?
  else
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    status=124
  fi
  BACKGROUND_PIDS="${BACKGROUND_PIDS/ $pid/}"
  RUN_STATUS=$status
}

echo "=== Legacy Hash Atomic Publication Tests ==="

echo -n "Collection interruption preserves both published manifests... "
COLLECTION_REPO=$(new_fixture collection)
cp "$COLLECTION_REPO/scripts/legacy-skill-hashes.txt" "$COLLECTION_REPO/primary.before"
cp "$COLLECTION_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$COLLECTION_REPO/mirror.before"
if GOPHER_AI_REGEN_FAILPOINT=collection \
   /bin/bash "$COLLECTION_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >/dev/null 2>&1; then
  echo "FAIL (collection failpoint did not interrupt regeneration)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$COLLECTION_REPO/primary.before" "$COLLECTION_REPO/scripts/legacy-skill-hashes.txt" ||
     ! cmp -s "$COLLECTION_REPO/mirror.before" "$COLLECTION_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
  echo "FAIL (an existing manifest changed before collection completed)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Interrupted publication is detected and repaired before collection... "
PUBLICATION_REPO=$(new_fixture publication)
printf '%s\n' 'updated version' > "$PUBLICATION_REPO/plugins/example/skills/example/SKILL.md"
if GOPHER_AI_REGEN_FAILPOINT=after-primary-publish \
   /bin/bash "$PUBLICATION_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >/dev/null 2>&1; then
  echo "FAIL (publication failpoint did not interrupt regeneration)"
  ERRORS=$((ERRORS + 1))
elif cmp -s "$PUBLICATION_REPO/scripts/legacy-skill-hashes.txt" \
           "$PUBLICATION_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
  echo "FAIL (failure injection did not expose the two-rename publication gap)"
  ERRORS=$((ERRORS + 1))
elif [ ! -f "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
  echo "FAIL (interrupted publication left no recovery marker)"
  ERRORS=$((ERRORS + 1))
else
  # Simulate the lock and same-directory staging residue that SIGKILL would
  # leave behind after the first rename.
  mkdir "$PUBLICATION_REPO/scripts/.regen-legacy-hashes.lock"
  printf '%s\n' '99999999' > "$PUBLICATION_REPO/scripts/.regen-legacy-hashes.lock/pid"
  touch \
    "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.primary.orphan" \
    "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.transaction.orphan" \
    "$PUBLICATION_REPO/plugins/go-workflow/hooks/.legacy-skill-hashes.mirror.orphan"

  if GOPHER_AI_REGEN_FAILPOINT=collection \
     /bin/bash "$PUBLICATION_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >/dev/null 2>&1; then
    echo "FAIL (recovery probe unexpectedly completed collection)"
    ERRORS=$((ERRORS + 1))
  elif ! cmp -s "$PUBLICATION_REPO/scripts/legacy-skill-hashes.txt" \
               "$PUBLICATION_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
    echo "FAIL (the missed mirror rename was not repaired before collection)"
    ERRORS=$((ERRORS + 1))
  elif [ -e "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.transaction" ] ||
       [ -e "$PUBLICATION_REPO/scripts/.regen-legacy-hashes.lock" ] ||
       [ -e "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.primary.orphan" ] ||
       [ -e "$PUBLICATION_REPO/scripts/.legacy-skill-hashes.transaction.orphan" ] ||
       [ -e "$PUBLICATION_REPO/plugins/go-workflow/hooks/.legacy-skill-hashes.mirror.orphan" ]; then
    echo "FAIL (recovery left transaction, stale lock, or staged files behind)"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

echo -n "Check mode works from a read-only checkout... "
READ_ONLY_REPO=$(new_fixture read-only-check)
READ_ONLY_LOG="$TEST_ROOT/read-only-check.log"
chmod a-w "$READ_ONLY_REPO/scripts" "$READ_ONLY_REPO/plugins/go-workflow/hooks"
run_with_deadline "$READ_ONLY_LOG" \
  /bin/bash "$READ_ONLY_REPO/scripts/regen-legacy-hashes.sh" --check --base-ref main
chmod u+w "$READ_ONLY_REPO/scripts" "$READ_ONLY_REPO/plugins/go-workflow/hooks"
if [ "$RUN_STATUS" -eq 124 ]; then
  echo "FAIL (check mode waited indefinitely for an unwritable publication lock)"
  ERRORS=$((ERRORS + 1))
elif [ "$RUN_STATUS" -ne 0 ]; then
  echo "FAIL (check mode exited $RUN_STATUS)"
  sed -n '1,20p' "$READ_ONLY_LOG"
  ERRORS=$((ERRORS + 1))
elif [ -e "$READ_ONLY_REPO/scripts/.regen-legacy-hashes.lock" ]; then
  echo "FAIL (check mode created a repository-local publication lock)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "A reused lock-owner PID is recognized as stale... "
REUSED_PID_REPO=$(new_fixture reused-pid)
REUSED_PID_LOG="$TEST_ROOT/reused-pid.log"
mkdir "$REUSED_PID_REPO/scripts/.regen-legacy-hashes.lock"
printf '%s\n' "$$" > "$REUSED_PID_REPO/scripts/.regen-legacy-hashes.lock/pid"
printf '%s\n' '1' > "$REUSED_PID_REPO/scripts/.regen-legacy-hashes.lock/created-at"
run_with_deadline "$REUSED_PID_LOG" \
  env GOPHER_AI_REGEN_FAILPOINT=collection \
  /bin/bash "$REUSED_PID_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
if [ "$RUN_STATUS" -eq 124 ]; then
  echo "FAIL (the unrelated live PID was treated as the lock owner)"
  rm -rf "$REUSED_PID_REPO/scripts/.regen-legacy-hashes.lock"
  ERRORS=$((ERRORS + 1))
elif ! grep -q 'injected legacy hash regeneration failure at collection' "$REUSED_PID_LOG"; then
  echo "FAIL (stale-lock recovery did not reach collection)"
  sed -n '1,20p' "$REUSED_PID_LOG"
  ERRORS=$((ERRORS + 1))
elif [ -e "$REUSED_PID_REPO/scripts/.regen-legacy-hashes.lock" ]; then
  echo "FAIL (stale-lock recovery left the replacement lock behind)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi

echo -n "Concurrent regenerations serialize on one publication lock... "
CONCURRENT_REPO=$(new_fixture concurrent)
RELEASE_FILE="$TEST_ROOT/release-first-writer"
READY_FILE="$RELEASE_FILE.ready"
WAIT_FILE="$TEST_ROOT/second-writer-waiting"
FIRST_LOG="$TEST_ROOT/first-writer.log"
SECOND_LOG="$TEST_ROOT/second-writer.log"
GOPHER_AI_REGEN_TEST_HOLD_LOCK="$RELEASE_FILE" \
  /bin/bash "$CONCURRENT_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$FIRST_LOG" 2>&1 &
FIRST_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $FIRST_PID"

READY=false
for _ in $(seq 1 100); do
  if [ -e "$READY_FILE" ]; then
    READY=true
    break
  fi
  if ! kill -0 "$FIRST_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if [ "$READY" != true ]; then
  echo "FAIL (first writer never exposed the held-lock test point)"
  ERRORS=$((ERRORS + 1))
else
  GOPHER_AI_REGEN_TEST_LOCK_WAIT_FILE="$WAIT_FILE" \
    /bin/bash "$CONCURRENT_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$SECOND_LOG" 2>&1 &
  SECOND_PID=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $SECOND_PID"

  WAITING=false
  for _ in $(seq 1 100); do
    if [ -e "$WAIT_FILE" ]; then
      WAITING=true
      break
    fi
    if ! kill -0 "$SECOND_PID" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done
  touch "$RELEASE_FILE"

  FIRST_STATUS=0
  SECOND_STATUS=0
  wait "$FIRST_PID" || FIRST_STATUS=$?
  wait "$SECOND_PID" || SECOND_STATUS=$?
  BACKGROUND_PIDS=""

  if [ "$WAITING" != true ]; then
    echo "FAIL (second writer did not report waiting on the publication lock)"
    ERRORS=$((ERRORS + 1))
  elif [ "$FIRST_STATUS" -ne 0 ] || [ "$SECOND_STATUS" -ne 0 ]; then
    echo "FAIL (writers exited $FIRST_STATUS and $SECOND_STATUS)"
    sed -n '1,20p' "$FIRST_LOG"
    sed -n '1,20p' "$SECOND_LOG"
    ERRORS=$((ERRORS + 1))
  elif ! cmp -s "$CONCURRENT_REPO/scripts/legacy-skill-hashes.txt" \
               "$CONCURRENT_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
    echo "FAIL (serialized writers left divergent manifests)"
    ERRORS=$((ERRORS + 1))
  elif [ -e "$CONCURRENT_REPO/scripts/.regen-legacy-hashes.lock" ] ||
       [ -e "$CONCURRENT_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
    echo "FAIL (successful writers left lock or transaction state behind)"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS legacy hash publication test(s) failed"
  exit 1
fi

echo "All legacy hash atomic publication tests passed."
