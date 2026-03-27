---
name: systematic-debugging
description: |
  WHEN: User is debugging Go code, investigating bugs, analyzing test failures, encountering
  unexpected behavior, reading stack traces, diagnosing race conditions, fixing flaky tests,
  or saying "why is this broken", "this doesn't work", "test is failing", "getting an error".
  Also activate when investigating panics, goroutine deadlocks, data corruption, or any
  situation where the root cause is not immediately obvious.
  Trigger this skill liberally for ANY debugging or bug investigation work in Go.
  WHEN NOT: Writing new features from scratch, code review without a specific bug,
  questions entirely unrelated to debugging or troubleshooting
---

# Systematic Debugging

**IRON LAW: NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.**

Do not guess. Do not "just try changing X." Do not apply quick fixes. Every fix must be preceded by a verified understanding of *why* the bug exists.

## Phase 1: Root Cause Investigation

Before touching any code:

1. **Read the error completely** — full error message, full stack trace, full log output. Do not skim.
2. **Reproduce consistently** — write a failing test or find a reliable reproduction command:
   ```bash
   go test ./path/to/package/... -run TestName -v -count=1
   ```
   For race conditions, use the race detector:
   ```bash
   go test ./path/to/package/... -race -count=5
   ```
3. **Check recent changes** — use `git log --oneline -20` and `git blame` on the affected code. What changed last?
4. **Trace data flow backward** — start at the error site and trace backward through the call chain. At each step ask: "What called this? What value did it pass? Where did that value come from?"
5. **Gather evidence at boundaries** — in multi-layer systems (handler → service → repository → database), add temporary diagnostic logging at each layer boundary to narrow the fault location.

**Go-specific investigation tools:**
- `go vet ./...` — catches common mistakes (printf format mismatches, unreachable code, mutex misuse)
- `go test -race` — detects data races that cause intermittent failures
- `dlv test ./path/to/package -- -test.run TestName` — step through with delve when logic flow is unclear
- Stack trace reading: goroutine state (`running`, `chan receive`, `select`, `semacquire`) reveals deadlocks and blocking

**HARD GATE: Do NOT proceed to Phase 2 until you can state the reproduction steps AND have a failing test or command that demonstrates the bug.**

## Phase 2: Pattern Analysis

1. **Find similar working code** — grep the codebase for similar patterns that work correctly
2. **Read the working implementation completely** — do not skim
3. **Identify ALL differences** between the working and broken code — not just the obvious ones
4. **Understand dependencies and assumptions** — what does the broken code assume about its inputs, environment, or ordering that the working code does not?

## Phase 3: Hypothesis Testing

1. **Form ONE specific hypothesis** — write it down: "The bug occurs because X passes Y to Z, but Z expects W"
2. **Design a minimal test** — change ONE variable to test the hypothesis. Do not make multiple changes.
3. **Run the test and evaluate** — did the result confirm or refute the hypothesis?
4. **If refuted** — return to Phase 1 with new information. Do not stack more hypotheses.

**HARD GATE: If 3 fix attempts fail, STOP.** Do not attempt a 4th fix. Instead:
- Present findings to the user: what you know, what you tried, what failed
- Discuss whether the issue is architectural (wrong design) rather than a bug (wrong implementation)
- Ask for guidance before proceeding

**Red flags that you're violating the process:**
- "Quick fix for now" — there are no quick fixes, only root causes
- "Just try changing X" — hypothesize first, then test
- "One more attempt" after 3 failures — stop and discuss
- Skipping the reproduction step — you cannot fix what you cannot reproduce

## Phase 4: Implementation

1. **The failing test already exists** from Phase 1 — confirm it still fails
2. **Implement a single fix** addressing the root cause, not the symptom
3. **Run the full test suite** — the fix must not break other tests:
   ```bash
   go test ./... -count=1
   ```
4. **Run with race detector** if concurrency is involved:
   ```bash
   go test ./... -race -count=1
   ```
5. **Add defense-in-depth validation** where appropriate:
   - **Entry point**: validate inputs at the public API boundary
   - **Business logic**: assert preconditions at the start of critical functions
   - **Environment**: guard against dangerous operations in wrong contexts (e.g., destructive DB calls outside transactions)

## Condition-Based Waiting (For Flaky Tests)

**Never use `time.Sleep` to wait for conditions in tests.** Sleep-based waits are the #1 cause of flaky tests.

Instead, use condition-based waiting:

```go
// Use testify's Eventually for polling conditions
assert.Eventually(t, func() bool {
    return getResult() != nil
}, 5*time.Second, 10*time.Millisecond, "expected result to be available")

// Or use channels for event-based waiting
select {
case result := <-resultCh:
    assert.Equal(t, expected, result)
case <-time.After(5 * time.Second):
    t.Fatal("timed out waiting for result")
}
```

**When `time.Sleep` IS acceptable:**
- After a condition-based wait, to allow a documented settling period
- Based on documented system timing (e.g., known cache TTL)
- Always with an explanatory comment stating *why* this specific duration

## Testing Anti-Patterns to Watch For

- **Testing mock behavior instead of real behavior** — if your assertion checks that a mock was called, you're testing the mock, not the code
- **Test-only methods in production code** — cleanup/destroy methods that only tests use belong in test helpers
- **Mocking without understanding** — before mocking, document all side effects of the real method and which ones your test needs
- **Tests that pass immediately** — a test written after a fix that passes on first run proves nothing; it should have failed before the fix
