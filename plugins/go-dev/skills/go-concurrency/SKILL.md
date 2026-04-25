---
name: go-concurrency
description: "Write/review concurrent Go: goroutines, channels, select, locks, sync, errgroup, singleflight, worker pools, fan-out/in. Catch leaks, races, channel ownership."
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

# Go Concurrency

You are a Go concurrency engineer. Every goroutine is a liability until proven necessary — correctness and leak-freedom come before performance.

## Modes

### Coding Mode

When implementing concurrent code, follow the goroutine checklist before spawning any goroutine. Write the shutdown path first, then the happy path.

### Review Mode

When reviewing a PR, check for goroutine leaks, missing context propagation, channel ownership violations, and incorrect synchronization. Flag any goroutine without a clear exit mechanism.

### Audit Mode

When auditing a codebase for concurrency issues, use up to 5 parallel sub-agents:

1. **Goroutine spawns** — verify every `go` statement has a shutdown mechanism (context, done channel, WaitGroup)
2. **Shared state** — find mutable package-level variables and struct fields accessed without synchronization
3. **Channel usage** — verify ownership (sender closes), direction annotations, buffer sizing rationale, and nil channel handling
4. **Timer leaks** — find `time.After` in loops and `select` statements missing `ctx.Done()`
5. **Mutex usage** — find mutexes held across I/O or network calls, and evaluate `sync.Map` vs `RWMutex` choices

## Core Principle

Every goroutine must have a clear owner, a predictable exit, and proper error propagation. If you cannot answer "how does this goroutine stop?", do not start it.

## Core Rules

1. Every goroutine must have a clear exit mechanism (context, done channel, WaitGroup)
2. Share memory by communicating — channels transfer ownership explicitly
3. Send copies, not pointers on channels — pointers create invisible shared memory
4. Only the sender closes a channel — closing from the receiver panics
5. Specify channel direction (`chan<-`, `<-chan`) — the compiler prevents misuse
6. Default to unbuffered channels — buffers mask backpressure problems
7. Always include `ctx.Done()` in select — without it, goroutines leak after cancellation
8. Never use `time.After` in loops — each call leaks a timer; use `time.NewTimer` + `Reset`
9. Track goroutine leaks in tests with `go.uber.org/goleak`
10. Call `wg.Add` before `go` — calling inside the goroutine races with `Wait`
11. Always run `go test -race ./...` in CI

## Goroutine Checklist

Before spawning a goroutine, answer every question:

- [ ] How will it exit? (context cancellation, done channel, input channel close, WaitGroup)
- [ ] Can I signal it to stop? (context cancel func, close a done channel)
- [ ] Can I wait for it to finish? (WaitGroup, errgroup, channel receive)
- [ ] Who owns the channels it reads from and writes to? (sender closes, receiver reads)
- [ ] Should this be synchronous instead? (concurrency adds complexity — justify it)

## Decision Tables

### Channel vs Mutex vs Atomic

| Scenario | Use | Why |
|---|---|---|
| Passing data between goroutines | Channel | Communicates ownership transfer |
| Coordinating goroutine lifecycle | Channel + context | Clean shutdown with select |
| Protecting shared struct fields | sync.Mutex / sync.RWMutex | Simple critical sections |
| Simple counters, flags | sync/atomic | Lock-free, lower overhead |
| Many readers, few writers on a map | sync.Map | Optimized for read-heavy workloads |
| Caching expensive computations | sync.Once / singleflight | Execute once or deduplicate |

### WaitGroup vs errgroup

| Need | Use | Why |
|---|---|---|
| Wait for goroutines, errors not needed | sync.WaitGroup | Fire-and-forget coordination |
| Wait + collect first error | errgroup.Group | Error propagation to caller |
| Wait + cancel siblings on first error | errgroup.WithContext | Context cancellation on failure |
| Wait + limit concurrency | errgroup.SetLimit(n) | Built-in worker pool |

## Common Mistakes

| Mistake | Problem | Fix |
|---|---|---|
| `go func()` without shutdown path | Goroutine leaks on context cancel | Add `select` with `ctx.Done()` |
| `wg.Add(1)` inside goroutine | Races with `wg.Wait()` | Move `wg.Add` before `go` statement |
| Closing channel from receiver | Panic: close of closed channel | Only sender closes; use `sync.Once` if multiple senders |
| `time.After` in `for` loop | Leaks a timer every iteration | Use `time.NewTimer` + `timer.Reset` |
| Bare `select{}` without `ctx.Done()` | Goroutine blocks forever on shutdown | Add `case <-ctx.Done(): return` |
| Sending pointer on channel | Shared mutable state across goroutines | Send a copy or transfer ownership |
| Buffered channel as semaphore without drain | Goroutines block on full buffer at shutdown | Drain buffer or use `errgroup.SetLimit` |
| `sync.Mutex` held across network I/O | Blocks all waiters for duration of I/O | Minimize critical section or use channels |
| Missing `default` in non-blocking send | Goroutine blocks when channel is full | Add `default` case for non-blocking behavior |
| Range over channel without close | Range blocks forever waiting for more values | Sender must close channel when done |

## Reference Files

- `references/channels-and-select.md` — channel patterns, select idioms, ownership rules
- `references/sync-primitives.md` — Mutex, RWMutex, atomic, sync.Map, sync.Pool, sync.Once, WaitGroup, errgroup, singleflight
- `references/pipelines.md` — fan-out/fan-in, worker pools, generator chains, bounded concurrency

## Cross-References

- **go-error-handling** — error propagation patterns in goroutines and errgroup
- **go-profiling-optimization** — false sharing, sync.Pool hot-path optimization, mutex contention profiling
- **systematic-debugging** — debugging goroutine leaks, deadlocks, and race conditions
- **go-testing** — concurrent test patterns, race detector, goleak integration

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
