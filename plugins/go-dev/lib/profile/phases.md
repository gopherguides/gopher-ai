# Profile — Phases 2–4 + Optimization Patterns

Loaded by `commands/profile.md` Phases 2–4 and Phase 6.

## Phase 2: CPU Profiling

### Generate

```bash
go test -bench=. -cpuprofile=cpu.pprof -run=^$ ./target/path/
```

### Top consumers (cumulative — finds real bottlenecks)

```bash
go tool pprof -top -cum cpu.pprof 2>&1 | head -25
```

READ the output:

- **flat** = time spent ONLY in this function (not descendants)
- **cum** = cumulative time (this function + everything it calls)
- Sort by `cum` to find where time is actually spent
- The highest `cum%` functions are your primary targets

### Source annotations (drill into top 3 by cum)

```bash
go tool pprof -list=FunctionName cpu.pprof 2>&1
```

READ the annotated source:

- Time values on the LEFT show how much each LINE consumes
- This tells you the EXACT lines that are hot
- Look for: loops with per-iteration allocations, unbuffered I/O, string concatenation

### Callers and callees

```bash
go tool pprof -peek=FunctionName cpu.pprof 2>&1
```

Shows who calls the hot function and what it calls — helps understand the full hot path.

## Phase 3: Memory Profiling

### Generate

```bash
go test -bench=. -memprofile=mem.pprof -run=^$ ./target/path/
```

### Top allocators

```bash
go tool pprof -top -cum mem.pprof 2>&1 | head -25
```

Look for high allocation counts (`allocs`) and high allocation sizes (`bytes`).

### Drill into allocation sources (top 3)

```bash
go tool pprof -list=FunctionName mem.pprof 2>&1
```

READ the annotated source — identify which lines are allocating and how much.

### Escape Analysis

```bash
go build -gcflags="-m" ./target/path/ 2>&1
```

READ the output:

- `escapes to heap` — allocations that could potentially be optimized
- `does not escape` — already stack-allocated (good)
- `moved to heap` — variables the compiler couldn't keep on the stack
- Common escape triggers: returning pointers, storing in interfaces, closure captures

For more detail (shows inlining decisions too):

```bash
go build -gcflags="-m -m" ./target/path/ 2>&1 | head -50
```

## Phase 4: Trace Analysis (Concurrent Code Only)

Skip this phase if the target code does not use goroutines/channels/mutexes/sync primitives.

### Detect concurrency

```bash
rg -n 'go func|sync\.|chan |<-' ./target/path/*.go 2>/dev/null
```

If no concurrency found, skip to Phase 5.

### Generate trace

```bash
go test -trace=trace.out -run=^$ -bench=. ./target/path/
```

### Extract per-category profiles

```bash
go tool trace -pprof=net trace.out > trace-net.pprof 2>/dev/null      # Network blocking
go tool trace -pprof=sync trace.out > trace-sync.pprof 2>/dev/null    # Mutex/channel blocking
go tool trace -pprof=syscall trace.out > trace-syscall.pprof 2>/dev/null  # Syscall blocking
go tool trace -pprof=sched trace.out > trace-sched.pprof 2>/dev/null  # Scheduler latency
```

### Analyze each non-empty profile

```bash
for prof in trace-net.pprof trace-sync.pprof trace-syscall.pprof trace-sched.pprof; do
  if [ -s "$prof" ]; then
    echo "=== $prof ==="
    go tool pprof -top "$prof" 2>&1 | head -15
  fi
done
```

What to look for:

- **sync blocking** — lock contention; goroutines waiting on mutexes
- **sched latency** — too many goroutines saturating the scheduler
- **net blocking** — network I/O blocking goroutines
- **syscall blocking** — system calls holding goroutines

## Phase 6: Optimization Patterns

| Bottleneck | Optimization |
|-----------|-------------|
| Unbuffered I/O reads | Wrap reader in `bufio.NewReader(rd)` |
| String concatenation in loop | Use `strings.Builder` or `[]byte` |
| Per-call buffer allocation | Accept reusable `[]byte` parameter |
| Slice growing without capacity | `make([]T, 0, expectedCap)` |
| `fmt.Sprintf` in hot path | Use `strconv` functions directly |
| Interface boxing in hot path | Use concrete types |
| Heap escapes from pointers | Return values instead of pointers for small structs |
| Lock contention | Reduce critical section, use `sync.RWMutex`, shard data |
| Goroutine overhead | Batch work per goroutine instead of one-per-item |
| GC pressure from many small allocs | `sync.Pool` for frequently allocated objects |

### Verification (after each optimization)

```bash
# Save before
go test -bench=BenchmarkTarget -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-before.bench

# Apply the change, then re-run tests:
go test ./target/path/ -count=1

# Save after
go test -bench=BenchmarkTarget -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-after.bench

# Compare — require p < 0.05
benchstat .profile-before.bench .profile-after.bench
```

If p ≥ 0.05, the improvement is not statistically significant. Either increase `-count` or accept that the optimization is not effective.

### Re-profile after each fix

A successful optimization usually shifts the hotspot. Re-profile to confirm:

```bash
go test -bench=. -cpuprofile=cpu-after.pprof -run=^$ ./target/path/
go tool pprof -top -cum cpu-after.pprof 2>&1 | head -15
```
