# Decision Gates

Every workflow decision is either driver-resolvable, missing intent, or a hard
invariant. Classify it before acting.

## Driver-resolvable gate

A capable driver resolves technical and workflow choices from the user request,
repository state, issue or pull request context, configuration, prior workflow
state, and command output. It does not request input merely because an older
workflow presented an option menu.

Before acting, state:

```text
Decision: <selected action>
Evidence: <facts that determine or constrain the action>
Rationale: <why this is the safest complete action>
```

Prefer the action that is in scope, reversible, preserves unrelated work, and
keeps top-level completion criteria enforceable. Follow any gate-specific
ordering in the calling workflow. Continue after stating the rationale.

## Missing-intent gate

Human intent is required only when evidence cannot determine one of these:

- a missing issue, pull request, worktree, or action target
- consent to copy environment files or secrets
- issue semantics that remain ambiguous after labels, body, and comments
- product behavior or acceptance criteria not specified by available context
- permission to replace an explicitly selected review backend
- a choice among equally valid worktrees
- optional branch deletion

First exhaust the evidence listed by the calling workflow. If intent is still
missing, request it through the active surface's native structured-input
capability when available. Otherwise ask one concise question in the final
response and stop.

Do not perform the dependent action, advance the workflow phase, emit a
completion marker, or claim completion before the answer arrives. A persistent
workflow must preserve its current phase and record that it is awaiting intent
before returning the question; the answer resumes that same gate.

## Hard invariant

A hard invariant has no valid bypass. Follow the calling workflow's
machine-readable incomplete outcome and stop. Never reinterpret a hard stop as
a driver or human-intent choice.
