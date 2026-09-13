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
  local attempts="${RUN_DEADLINE_ATTEMPTS:-40}"

  "$@" >"$log_file" 2>&1 &
  pid=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $pid"
  for _ in $(seq 1 "$attempts"); do
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

process_is_executing() {
  local pid="$1"
  local state

  kill -0 "$pid" 2>/dev/null || return 1
  state=$(ps -o stat= -p "$pid" 2>/dev/null | awk 'NR == 1 { print $1 }')
  [ -n "$state" ] && [ "${state#Z}" = "$state" ]
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

echo -n "A hard-killed writer releases the publication lock... "
HARD_KILL_REPO=$(new_fixture hard-kill)
HARD_KILL_CHILD="$TEST_ROOT/hard-kill-collection-child"
HARD_KILL_READY="$HARD_KILL_CHILD.ready"
HARD_KILL_LOG="$TEST_ROOT/hard-kill.log"
HARD_KILL_RECOVERY_LOG="$TEST_ROOT/hard-kill-recovery.log"
GOPHER_AI_REGEN_TEST_COLLECTION_CHILD="$HARD_KILL_CHILD" \
  /bin/bash "$HARD_KILL_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$HARD_KILL_LOG" 2>&1 &
HARD_KILL_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $HARD_KILL_PID"

HARD_KILL_HELD=false
for _ in $(seq 1 100); do
  if [ -e "$HARD_KILL_READY" ]; then
    HARD_KILL_HELD=true
    break
  fi
  if ! kill -0 "$HARD_KILL_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if [ "$HARD_KILL_HELD" != true ]; then
  echo "FAIL (writer never exposed the held-lock test point)"
  ERRORS=$((ERRORS + 1))
else
  kill -9 "$HARD_KILL_PID" 2>/dev/null || true
  wait "$HARD_KILL_PID" 2>/dev/null || true
  BACKGROUND_PIDS="${BACKGROUND_PIDS/ $HARD_KILL_PID/}"
  run_with_deadline "$HARD_KILL_RECOVERY_LOG" \
    env GOPHER_AI_REGEN_FAILPOINT=collection \
    /bin/bash "$HARD_KILL_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
  if [ "$RUN_STATUS" -eq 124 ]; then
    echo "FAIL (successor waited on a lock whose owner was hard-killed)"
    ERRORS=$((ERRORS + 1))
  elif ! grep -q 'injected legacy hash regeneration failure at collection' "$HARD_KILL_RECOVERY_LOG"; then
    echo "FAIL (successor did not acquire the released kernel lock)"
    sed -n '1,20p' "$HARD_KILL_RECOVERY_LOG"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

echo -n "A waiting writer responds promptly to TERM... "
CANCEL_REPO=$(new_fixture cancel-waiter)
CANCEL_RELEASE="$TEST_ROOT/cancel-waiter-release"
CANCEL_READY="$CANCEL_RELEASE.ready"
CANCEL_WAITING="$TEST_ROOT/cancel-waiter-waiting"
CANCEL_HOLDER_LOG="$TEST_ROOT/cancel-holder.log"
CANCEL_WAITER_LOG="$TEST_ROOT/cancel-waiter.log"
GOPHER_AI_REGEN_TEST_HOLD_LOCK="$CANCEL_RELEASE" \
  /bin/bash "$CANCEL_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$CANCEL_HOLDER_LOG" 2>&1 &
CANCEL_HOLDER_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $CANCEL_HOLDER_PID"

CANCEL_HOLDER_READY=false
for _ in $(seq 1 100); do
  if [ -e "$CANCEL_READY" ]; then
    CANCEL_HOLDER_READY=true
    break
  fi
  sleep 0.05
done

if [ "$CANCEL_HOLDER_READY" = true ]; then
  GOPHER_AI_REGEN_TEST_LOCK_WAIT_FILE="$CANCEL_WAITING" \
    /bin/bash "$CANCEL_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$CANCEL_WAITER_LOG" 2>&1 &
  CANCEL_WAITER_PID=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $CANCEL_WAITER_PID"
  for _ in $(seq 1 100); do
    [ ! -e "$CANCEL_WAITING" ] || break
    sleep 0.05
  done
  kill -TERM "$CANCEL_WAITER_PID" 2>/dev/null || true
  CANCELLED=false
  for _ in $(seq 1 40); do
    if ! kill -0 "$CANCEL_WAITER_PID" 2>/dev/null; then
      CANCELLED=true
      break
    fi
    sleep 0.05
  done
  CANCEL_WAITER_STATUS=0
  if [ "$CANCELLED" = true ]; then
    wait "$CANCEL_WAITER_PID" || CANCEL_WAITER_STATUS=$?
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $CANCEL_WAITER_PID/}"
  fi
  touch "$CANCEL_RELEASE"
  CANCEL_HOLDER_STATUS=0
  wait "$CANCEL_HOLDER_PID" || CANCEL_HOLDER_STATUS=$?
  BACKGROUND_PIDS="${BACKGROUND_PIDS/ $CANCEL_HOLDER_PID/}"
  if [ "$CANCELLED" != true ]; then
    wait "$CANCEL_WAITER_PID" 2>/dev/null || true
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $CANCEL_WAITER_PID/}"
    echo "FAIL (waiter ignored TERM until the holder released the lock)"
    ERRORS=$((ERRORS + 1))
  elif [ "$CANCEL_WAITER_STATUS" -ne 143 ]; then
    echo "FAIL (waiter exited $CANCEL_WAITER_STATUS instead of 143)"
    sed -n '1,20p' "$CANCEL_WAITER_LOG"
    ERRORS=$((ERRORS + 1))
  elif [ "$CANCEL_HOLDER_STATUS" -ne 0 ]; then
    echo "FAIL (lock holder exited $CANCEL_HOLDER_STATUS)"
    sed -n '1,20p' "$CANCEL_HOLDER_LOG"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
else
  echo "FAIL (lock holder never exposed the wait point)"
  ERRORS=$((ERRORS + 1))
fi

echo -n "A writer aborts if its lock guardian exits... "
GUARD_REPO=$(new_fixture guardian-exit)
GUARD_RELEASE="$TEST_ROOT/guardian-exit-release"
GUARD_READY="$GUARD_RELEASE.ready"
GUARD_PID_FILE="$TEST_ROOT/guardian-exit.pid"
GUARD_LOG="$TEST_ROOT/guardian-exit.log"
GUARD_SUCCESSOR_LOG="$TEST_ROOT/guardian-exit-successor.log"
cp "$GUARD_REPO/scripts/legacy-skill-hashes.txt" "$GUARD_REPO/guardian-primary.before"
cp "$GUARD_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt" "$GUARD_REPO/guardian-mirror.before"
GOPHER_AI_REGEN_TEST_HOLD_LOCK="$GUARD_RELEASE" \
GOPHER_AI_REGEN_TEST_LOCK_GUARD_PID_FILE="$GUARD_PID_FILE" \
  /bin/bash "$GUARD_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$GUARD_LOG" 2>&1 &
GUARD_WRITER_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $GUARD_WRITER_PID"

GUARD_HELD=false
for _ in $(seq 1 100); do
  if [ -e "$GUARD_READY" ] && [ -s "$GUARD_PID_FILE" ]; then
    GUARD_HELD=true
    break
  fi
  if ! kill -0 "$GUARD_WRITER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if [ "$GUARD_HELD" != true ]; then
  echo "FAIL (writer never exposed the guardian test point)"
  ERRORS=$((ERRORS + 1))
else
  read -r GUARD_PID < "$GUARD_PID_FILE"
  kill -9 "$GUARD_PID" 2>/dev/null || true
  GUARD_ABORTED=false
  for _ in $(seq 1 40); do
    if ! kill -0 "$GUARD_WRITER_PID" 2>/dev/null; then
      GUARD_ABORTED=true
      break
    fi
    sleep 0.05
  done
  GUARD_WRITER_STATUS=0
  if [ "$GUARD_ABORTED" = true ]; then
    wait "$GUARD_WRITER_PID" || GUARD_WRITER_STATUS=$?
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $GUARD_WRITER_PID/}"
  fi

  run_with_deadline "$GUARD_SUCCESSOR_LOG" \
    env GOPHER_AI_REGEN_FAILPOINT=collection \
    /bin/bash "$GUARD_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
  if [ "$GUARD_ABORTED" != true ]; then
    kill "$GUARD_WRITER_PID" 2>/dev/null || true
    wait "$GUARD_WRITER_PID" 2>/dev/null || true
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $GUARD_WRITER_PID/}"
    echo "FAIL (writer continued after its guardian exited)"
    ERRORS=$((ERRORS + 1))
  elif [ "$GUARD_WRITER_STATUS" -eq 0 ] ||
       ! grep -q 'lost legacy hash publication lock' "$GUARD_LOG"; then
    echo "FAIL (writer did not report the lost publication lock)"
    sed -n '1,20p' "$GUARD_LOG"
    ERRORS=$((ERRORS + 1))
  elif ! cmp -s "$GUARD_REPO/guardian-primary.before" "$GUARD_REPO/scripts/legacy-skill-hashes.txt" ||
       ! cmp -s "$GUARD_REPO/guardian-mirror.before" "$GUARD_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
    echo "FAIL (writer published after losing its lock guardian)"
    ERRORS=$((ERRORS + 1))
  elif [ "$RUN_STATUS" -eq 124 ]; then
    echo "FAIL (successor did not acquire the released guardian lock)"
    ERRORS=$((ERRORS + 1))
  elif ! grep -q 'injected legacy hash regeneration failure at collection' "$GUARD_SUCCESSOR_LOG"; then
    echo "FAIL (successor did not reach collection after guardian exit)"
    sed -n '1,20p' "$GUARD_SUCCESSOR_LOG"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

echo -n "A lock-losing writer preserves its successor's transaction marker... "
MARKER_REPO=$(new_fixture marker-successor)
MARKER_RELEASE="$TEST_ROOT/marker-successor-release"
MARKER_READY="$MARKER_RELEASE.ready"
MARKER_GUARD_PID_FILE="$TEST_ROOT/marker-successor-guardian.pid"
MARKER_FIRST_LOG="$TEST_ROOT/marker-successor-first.log"
MARKER_SECOND_LOG="$TEST_ROOT/marker-successor-second.log"
MARKER_RECOVERY_LOG="$TEST_ROOT/marker-successor-recovery.log"
printf '%s\n' 'first publication' > "$MARKER_REPO/plugins/example/skills/example/SKILL.md"
GOPHER_AI_REGEN_TEST_HOLD_AFTER_MIRROR_PUBLISH="$MARKER_RELEASE" \
GOPHER_AI_REGEN_TEST_LOCK_GUARD_PID_FILE="$MARKER_GUARD_PID_FILE" \
  /bin/bash "$MARKER_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$MARKER_FIRST_LOG" 2>&1 &
MARKER_FIRST_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $MARKER_FIRST_PID"

MARKER_FIRST_READY=false
for _ in $(seq 1 100); do
  if [ -e "$MARKER_READY" ] && [ -s "$MARKER_GUARD_PID_FILE" ]; then
    MARKER_FIRST_READY=true
    break
  fi
  if ! kill -0 "$MARKER_FIRST_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if [ "$MARKER_FIRST_READY" != true ]; then
  echo "FAIL (first writer never reached post-publication hold)"
  ERRORS=$((ERRORS + 1))
else
  read -r MARKER_GUARD_PID < "$MARKER_GUARD_PID_FILE"
  kill -9 "$MARKER_GUARD_PID" 2>/dev/null || true
  printf '%s\n' 'successor publication' > "$MARKER_REPO/plugins/example/skills/example/SKILL.md"
  run_with_deadline "$MARKER_SECOND_LOG" \
    env GOPHER_AI_REGEN_FAILPOINT=after-primary-publish \
    /bin/bash "$MARKER_REPO/scripts/regen-legacy-hashes.sh" --base-ref main

  MARKER_SECOND_STATUS=$RUN_STATUS
  MARKER_GAP_READY=false
  if [ "$MARKER_SECOND_STATUS" -eq 97 ] &&
     [ -f "$MARKER_REPO/scripts/.legacy-skill-hashes.transaction" ] &&
     ! cmp -s "$MARKER_REPO/scripts/legacy-skill-hashes.txt" \
              "$MARKER_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
    MARKER_GAP_READY=true
  fi

  touch "$MARKER_RELEASE"
  MARKER_FIRST_STATUS=0
  wait "$MARKER_FIRST_PID" || MARKER_FIRST_STATUS=$?
  BACKGROUND_PIDS="${BACKGROUND_PIDS/ $MARKER_FIRST_PID/}"

  if [ "$MARKER_GAP_READY" = true ] &&
     [ -f "$MARKER_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
    run_with_deadline "$MARKER_RECOVERY_LOG" \
      env GOPHER_AI_REGEN_FAILPOINT=collection \
      /bin/bash "$MARKER_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
    MARKER_RECOVERY_STATUS=$RUN_STATUS
  else
    MARKER_RECOVERY_STATUS=125
  fi

  if [ "$MARKER_SECOND_STATUS" -ne 97 ]; then
    echo "FAIL (successor did not stop after publishing its primary manifest)"
    sed -n '1,20p' "$MARKER_SECOND_LOG"
    ERRORS=$((ERRORS + 1))
  elif [ "$MARKER_GAP_READY" != true ]; then
    echo "FAIL (successor did not leave a recoverable publication gap)"
    ERRORS=$((ERRORS + 1))
  elif [ "$MARKER_FIRST_STATUS" -eq 0 ] ||
       ! grep -q 'lock guardian failed to remove the publication transaction marker' \
           "$MARKER_FIRST_LOG"; then
    echo "FAIL (first writer did not abort after losing its guardian)"
    sed -n '1,20p' "$MARKER_FIRST_LOG"
    ERRORS=$((ERRORS + 1))
  elif [ "$MARKER_RECOVERY_STATUS" -eq 125 ]; then
    echo "FAIL (first writer removed the successor's transaction marker)"
    ERRORS=$((ERRORS + 1))
  elif [ "$MARKER_RECOVERY_STATUS" -eq 124 ]; then
    echo "FAIL (recovery waited on a released publication lock)"
    ERRORS=$((ERRORS + 1))
  elif ! grep -q 'recovered interrupted legacy hash manifest publication' "$MARKER_RECOVERY_LOG" ||
       ! cmp -s "$MARKER_REPO/scripts/legacy-skill-hashes.txt" \
                "$MARKER_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt" ||
       [ -e "$MARKER_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
    echo "FAIL (successor publication was not recovered from its preserved marker)"
    sed -n '1,20p' "$MARKER_RECOVERY_LOG"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

echo -n "A lock-losing recovery preserves its successor's transaction marker... "
RECOVERY_REPO=$(new_fixture recovery-successor)
RECOVERY_RELEASE="$TEST_ROOT/recovery-successor-release"
RECOVERY_READY="$RECOVERY_RELEASE.ready"
RECOVERY_GUARD_PID_FILE="$TEST_ROOT/recovery-successor-guardian.pid"
RECOVERY_INITIAL_LOG="$TEST_ROOT/recovery-successor-initial.log"
RECOVERY_FIRST_LOG="$TEST_ROOT/recovery-successor-first.log"
RECOVERY_SECOND_LOG="$TEST_ROOT/recovery-successor-second.log"
RECOVERY_FINAL_LOG="$TEST_ROOT/recovery-successor-final.log"
printf '%s\n' 'initial interrupted publication' > \
  "$RECOVERY_REPO/plugins/example/skills/example/SKILL.md"
run_with_deadline "$RECOVERY_INITIAL_LOG" \
  env GOPHER_AI_REGEN_FAILPOINT=after-primary-publish \
  /bin/bash "$RECOVERY_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
RECOVERY_INITIAL_STATUS=$RUN_STATUS

if [ "$RECOVERY_INITIAL_STATUS" -ne 97 ] ||
   [ ! -f "$RECOVERY_REPO/scripts/.legacy-skill-hashes.transaction" ] ||
   cmp -s "$RECOVERY_REPO/scripts/legacy-skill-hashes.txt" \
         "$RECOVERY_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
  echo "FAIL (fixture did not begin with a recoverable publication gap)"
  sed -n '1,20p' "$RECOVERY_INITIAL_LOG"
  ERRORS=$((ERRORS + 1))
else
  GOPHER_AI_REGEN_TEST_HOLD_AFTER_RECOVERY="$RECOVERY_RELEASE" \
  GOPHER_AI_REGEN_TEST_LOCK_GUARD_PID_FILE="$RECOVERY_GUARD_PID_FILE" \
    /bin/bash "$RECOVERY_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$RECOVERY_FIRST_LOG" 2>&1 &
  RECOVERY_FIRST_PID=$!
  BACKGROUND_PIDS="$BACKGROUND_PIDS $RECOVERY_FIRST_PID"

  RECOVERY_FIRST_READY=false
  for _ in $(seq 1 100); do
    if [ -e "$RECOVERY_READY" ] && [ -s "$RECOVERY_GUARD_PID_FILE" ]; then
      RECOVERY_FIRST_READY=true
      break
    fi
    if ! kill -0 "$RECOVERY_FIRST_PID" 2>/dev/null; then
      break
    fi
    sleep 0.05
  done

  if [ "$RECOVERY_FIRST_READY" != true ]; then
    echo "FAIL (recovery writer never reached its marker-removal hold)"
    kill "$RECOVERY_FIRST_PID" 2>/dev/null || true
    wait "$RECOVERY_FIRST_PID" 2>/dev/null || true
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $RECOVERY_FIRST_PID/}"
    ERRORS=$((ERRORS + 1))
  else
    read -r RECOVERY_GUARD_PID < "$RECOVERY_GUARD_PID_FILE"
    kill -9 "$RECOVERY_GUARD_PID" 2>/dev/null || true
    printf '%s\n' 'successor after interrupted recovery' > \
      "$RECOVERY_REPO/plugins/example/skills/example/SKILL.md"
    run_with_deadline "$RECOVERY_SECOND_LOG" \
      env GOPHER_AI_REGEN_FAILPOINT=after-primary-publish \
      /bin/bash "$RECOVERY_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
    RECOVERY_SECOND_STATUS=$RUN_STATUS

    RECOVERY_SECOND_GAP=false
    if [ "$RECOVERY_SECOND_STATUS" -eq 97 ] &&
       [ -f "$RECOVERY_REPO/scripts/.legacy-skill-hashes.transaction" ] &&
       ! cmp -s "$RECOVERY_REPO/scripts/legacy-skill-hashes.txt" \
                "$RECOVERY_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt"; then
      RECOVERY_SECOND_GAP=true
    fi

    touch "$RECOVERY_RELEASE"
    RECOVERY_FIRST_STATUS=0
    wait "$RECOVERY_FIRST_PID" || RECOVERY_FIRST_STATUS=$?
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $RECOVERY_FIRST_PID/}"

    if [ "$RECOVERY_SECOND_GAP" = true ] &&
       [ -f "$RECOVERY_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
      run_with_deadline "$RECOVERY_FINAL_LOG" \
        env GOPHER_AI_REGEN_FAILPOINT=collection \
        /bin/bash "$RECOVERY_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
      RECOVERY_FINAL_STATUS=$RUN_STATUS
    else
      RECOVERY_FINAL_STATUS=125
    fi

    if [ "$RECOVERY_SECOND_STATUS" -ne 97 ]; then
      echo "FAIL (successor did not stop after publishing its primary manifest)"
      sed -n '1,20p' "$RECOVERY_SECOND_LOG"
      ERRORS=$((ERRORS + 1))
    elif [ "$RECOVERY_SECOND_GAP" != true ]; then
      echo "FAIL (successor did not leave a recoverable publication gap)"
      ERRORS=$((ERRORS + 1))
    elif [ "$RECOVERY_FIRST_STATUS" -eq 0 ] ||
         ! grep -q 'lock guardian failed to remove the publication transaction marker' \
             "$RECOVERY_FIRST_LOG"; then
      echo "FAIL (recovery writer did not abort after losing its guardian)"
      sed -n '1,20p' "$RECOVERY_FIRST_LOG"
      ERRORS=$((ERRORS + 1))
    elif [ "$RECOVERY_FINAL_STATUS" -eq 125 ]; then
      echo "FAIL (recovery writer removed the successor's transaction marker)"
      ERRORS=$((ERRORS + 1))
    elif [ "$RECOVERY_FINAL_STATUS" -eq 124 ]; then
      echo "FAIL (final recovery waited on a released publication lock)"
      ERRORS=$((ERRORS + 1))
    elif ! grep -q 'recovered interrupted legacy hash manifest publication' "$RECOVERY_FINAL_LOG" ||
         ! cmp -s "$RECOVERY_REPO/scripts/legacy-skill-hashes.txt" \
                  "$RECOVERY_REPO/plugins/go-workflow/hooks/legacy-skill-hashes.txt" ||
         [ -e "$RECOVERY_REPO/scripts/.legacy-skill-hashes.transaction" ]; then
      echo "FAIL (successor publication was not recovered from its preserved marker)"
      sed -n '1,20p' "$RECOVERY_FINAL_LOG"
      ERRORS=$((ERRORS + 1))
    else
      echo "OK"
    fi
  fi
fi

echo -n "An active collection responds promptly to TERM... "
ACTIVE_REPO=$(new_fixture cancel-collection)
ACTIVE_CHILD="$TEST_ROOT/cancel-collection-child"
ACTIVE_READY="$ACTIVE_CHILD.ready"
ACTIVE_CHILD_PID_FILE="$ACTIVE_CHILD.pid"
ACTIVE_LOG="$TEST_ROOT/cancel-collection.log"
ACTIVE_SUCCESSOR_LOG="$TEST_ROOT/cancel-collection-successor.log"
GOPHER_AI_REGEN_TEST_COLLECTION_CHILD="$ACTIVE_CHILD" \
GOPHER_AI_REGEN_TEST_COLLECTION_CHILD_SECONDS=30 \
  /bin/bash "$ACTIVE_REPO/scripts/regen-legacy-hashes.sh" --base-ref main >"$ACTIVE_LOG" 2>&1 &
ACTIVE_PID=$!
BACKGROUND_PIDS="$BACKGROUND_PIDS $ACTIVE_PID"

ACTIVE_COLLECTION_READY=false
for _ in $(seq 1 100); do
  if [ -e "$ACTIVE_READY" ]; then
    ACTIVE_COLLECTION_READY=true
    break
  fi
  if ! kill -0 "$ACTIVE_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

if [ "$ACTIVE_COLLECTION_READY" != true ]; then
  echo "FAIL (writer never entered the active collection test point)"
  ERRORS=$((ERRORS + 1))
else
  read -r ACTIVE_CHILD_PID < "$ACTIVE_CHILD_PID_FILE"
  kill -TERM "$ACTIVE_PID" 2>/dev/null || true
  ACTIVE_CANCELLED=false
  for _ in $(seq 1 40); do
    if ! kill -0 "$ACTIVE_PID" 2>/dev/null; then
      ACTIVE_CANCELLED=true
      break
    fi
    sleep 0.05
  done
  ACTIVE_STATUS=0
  if [ "$ACTIVE_CANCELLED" = true ]; then
    wait "$ACTIVE_PID" || ACTIVE_STATUS=$?
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $ACTIVE_PID/}"
  fi

  ACTIVE_CHILD_STOPPED=false
  for _ in $(seq 1 40); do
    if ! process_is_executing "$ACTIVE_CHILD_PID"; then
      ACTIVE_CHILD_STOPPED=true
      break
    fi
    sleep 0.05
  done

  run_with_deadline "$ACTIVE_SUCCESSOR_LOG" \
    env GOPHER_AI_REGEN_FAILPOINT=collection \
    /bin/bash "$ACTIVE_REPO/scripts/regen-legacy-hashes.sh" --base-ref main
  if [ "$ACTIVE_CANCELLED" != true ]; then
    kill "$ACTIVE_PID" 2>/dev/null || true
    wait "$ACTIVE_PID" 2>/dev/null || true
    BACKGROUND_PIDS="${BACKGROUND_PIDS/ $ACTIVE_PID/}"
    echo "FAIL (writer ignored TERM until collection completed)"
    ERRORS=$((ERRORS + 1))
  elif [ "$ACTIVE_STATUS" -ne 143 ]; then
    echo "FAIL (writer exited $ACTIVE_STATUS instead of 143)"
    sed -n '1,20p' "$ACTIVE_LOG"
    ERRORS=$((ERRORS + 1))
  elif [ "$ACTIVE_CHILD_STOPPED" != true ]; then
    echo "FAIL (collection child survived its canceled process group)"
    ERRORS=$((ERRORS + 1))
  elif [ "$RUN_STATUS" -eq 124 ]; then
    echo "FAIL (successor waited on the canceled collection's lock)"
    ERRORS=$((ERRORS + 1))
  elif ! grep -q 'injected legacy hash regeneration failure at collection' "$ACTIVE_SUCCESSOR_LOG"; then
    echo "FAIL (successor did not acquire the released publication lock)"
    sed -n '1,20p' "$ACTIVE_SUCCESSOR_LOG"
    ERRORS=$((ERRORS + 1))
  else
    echo "OK"
  fi
fi

echo -n "Concurrent regenerations serialize on one publication lock... "
CONCURRENT_REPO=$(new_fixture concurrent)
CONCURRENT_LINK="$TEST_ROOT/concurrent-link"
ln -s "$CONCURRENT_REPO" "$CONCURRENT_LINK"
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
    /bin/bash "$CONCURRENT_LINK/scripts/regen-legacy-hashes.sh" --base-ref main >"$SECOND_LOG" 2>&1 &
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
