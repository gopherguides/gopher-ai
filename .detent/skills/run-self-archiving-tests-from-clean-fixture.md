---
name: run-self-archiving-tests-from-clean-fixture
description: Run tests that copy or archive their repository without recursively ingesting Detent-local caches.
when_to_use: Use when a repository test copies its root while TMPDIR is nested beneath that root, causing recursive fixtures, oversized archives, or cleanup permission failures.
---

# Run self-archiving tests from a clean fixture

Keep all disposable files under Detent's temporary root, but do not run a
self-archiving test directly from the worktree that contains that root.

1. Create a git clone under `${TMPDIR}` so history-dependent tests still work.
2. Overlay the current working tree into the clone while excluding `.git`,
   `.detent`, and generated build output. This includes uncommitted files
   without copying Detent caches into the fixture.
3. Create a sibling runtime directory under `${TMPDIR}` and set `TMPDIR`,
   `TMP`, and `TEMP` to it for the test process.
4. If bare macOS `mktemp` calls still escape to the Darwin host directory, put
   a wrapper earlier on `PATH` that supplies a Detent-local template only when
   no template was provided. Forward explicit templates unchanged.
5. Run the test from the clean clone and preserve the fixture for Detent's
   per-turn cleanup instead of deleting it manually.

Confirm the clone contains every changed and untracked in-scope file before
using its result as validation evidence.
