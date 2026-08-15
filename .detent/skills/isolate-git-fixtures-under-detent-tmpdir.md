---
name: isolate-git-fixtures-under-detent-tmpdir
description: Prevent temporary test fixtures from inheriting the enclosing Git worktree when Detent routes temporary directories beneath the repository.
when_to_use: Use when tests create disposable directories under TMPDIR and commands inside them unexpectedly resolve the Detent worktree as their Git repository.
---

# Isolate Git Fixtures Under Detent TMPDIR

Resolve the temporary base from `TMPDIR`, `TMP`, or `TEMP`. When that base is inside the repository root, prepend it to `GIT_CEILING_DIRECTORIES` before creating fixtures.

```bash
FIXTURE_TMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
case "$FIXTURE_TMP_BASE/" in
  "$ROOT_DIR/"*)
    export GIT_CEILING_DIRECTORIES="$FIXTURE_TMP_BASE${GIT_CEILING_DIRECTORIES:+:$GIT_CEILING_DIRECTORIES}"
    ;;
esac
```

Keep fixtures under the Detent-provided temporary base. Initialize an explicit repository inside a fixture only when the test needs Git behavior.

Verify both the standalone focused test and the authoritative project gate. A passing nested invocation is not enough if the parent test already exports the ceiling.
