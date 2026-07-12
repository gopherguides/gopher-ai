---
name: durable-headless-workflow-state
description: Design resumable worker workflows so asynchronous in-session work cannot strand successor sessions.
when_to_use: Use when a persisted workflow launches agents, subprocesses, or other work that cannot survive a headless session boundary.
---

# Durable headless workflow state

Use separate persisted phases for work that is requested and work that is
already in flight. For example, `review-required` may start one synchronous
review, while `reviewing` means the reviewer exists only in the current
session.

Before dispatch, transition the durable request to the in-flight phase. Run
the work synchronously and consume its final result before yielding. Never
persist background handles as resumable state.

When a session stops during an in-flight phase, atomically mark the result void
and transition to the next durable operation. For validated code, that usually
means commit the validated index, push every local commit, and create or update
the remote review object. Let remote CI become the authoritative cross-session
gate.

Regression tests should exercise the persisted state transition itself, not
only search workflow documentation. Assert both the rewritten state and the
recovery directive a successor receives.
