---
name: go-profiling-optimization
description: Profile and optimize Go performance: pprof, allocations, escape analysis, sync.Pool, GOGC, benchmarks. Trigger for any Go perf, profiling, or runtime tuning question.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

<!-- cache:start -->

**Persona:** You are a Go performance engineer. You measure before you optimize, you optimize one thing at a time, and you verify with statistical rigor.

**Modes:**

- **Coding mode** — optimizing code. Follow the profiling workflow: baseline, profile, isolate, optimize, verify.
- **Review mode** — reviewing a PR for performance. Check for unnecessary allocations, missing benchmarks, premature optimization.
- **Audit mode** — auditing performance across a codebase. Use up to 4 parallel sub-agents targeting: CPU hotspots, memory allocations, concurrency bottlenecks, and I/O patterns.

> **Principle:** "Never optimize without profiling data. You will optimize the wrong thing."

# Go Profiling & Optimization

For hands-on profiling with automatic bottleneck detection and optimization, use `/profile <target>`.

## The Profiling Workflow

**NEVER optimize without profiling data.** Every optimization must be driven by evidence.

```
Baseline → Profile → Identify Bottleneck → Isolate → Optimize → Verify → Repeat
```

1. Establish a benchmark baseline with `go test -bench=. -benchmem -count=6`
2. Profile (CPU, then memory, then trace if concurrent)
3. Read pprof output — find the top 3 hotspots by cumulative time/allocations
4. Create isolation benchmarks for each hotspot
5. Apply ONE optimization at a time
6. Re-benchmark and compare with `benchstat old.bench new.bench`
7. Verify p-value < 0.05 (statistically significant improvement)
8. Repeat until diminishing returns

## Profile Types — When to Use Each

| Profile | Flag | Use When |
|---------|------|----------|
| CPU | `-cpuprofile=cpu.pprof` | Function is slow, high CPU usage |
| Memory (heap) | `-memprofile=mem.pprof` | High memory usage, GC pressure, many allocations |
| Block | `-blockprofile=block.pprof` | Goroutines blocked on channels or mutexes |
| Mutex | `-mutexprofile=mutex.pprof` | Lock contention suspected |
| Goroutine | `runtime/pprof.Lookup("goroutine")` | Goroutine leaks, too many goroutines |
| Trace | `-trace=trace.out` | Scheduling latency, GC pauses, concurrency issues |

**Start with CPU profiling.** If allocations are high (check `allocs/op` in benchmarks), add memory profiling. Use trace only for concurrency investigation.

## Reading pprof Output

### Key Metrics

- **flat / flat%**: Time spent ONLY in this function, not in functions it calls
- **cum / cum%**: Cumulative time — this function AND everything it calls
- **sum%**: Running total of flat% from top to bottom

**Always sort by cumulative (`-cum`)** to find where time is actually spent. A function with low `flat` but high `cum` is calling expensive children.

### Source Annotations

```bash
go tool pprof -list=FunctionName cpu.pprof
```

Shows source code with per-line timing. Time values on the LEFT show how much each line costs. This is your most powerful diagnostic — it tells you the EXACT lines to optimize.

### Callers and Callees

```bash
go tool pprof -peek=FunctionName cpu.pprof
```

Shows who calls the hot function and what it calls. Useful for understanding the full hot path.

## Escape Analysis

```bash
go build -gcflags="-m" ./...
```

Shows the compiler's allocation decisions:
- `escapes to heap` — variable allocated on heap (costs GC time)
- `does not escape` — stays on stack (free, automatic cleanup)
- `moved to heap` — compiler couldn't prove it stays in scope

### Common Escape Triggers

- Returning a pointer to a local variable
- Storing a value in an `interface{}` / `any` (interface boxing)
- Capturing a variable in a closure sent to a goroutine
- Passing a pointer to a function that the compiler can't inline
- Slice/map literals that grow beyond known bounds

### Avoiding Unnecessary Escapes

```go
// Escapes — returns pointer, forces heap allocation
func newThing() *Thing {
    t := Thing{Name: "x"}
    return &t
}

// Stays on stack — caller owns the memory
func initThing(t *Thing) {
    t.Name = "x"
}
```

## Common Optimization Techniques

### Preallocation

```go
// Avoid — grows slice multiple times, each grow allocates
items := []string{}
for _, v := range data {
    items = append(items, v)
}

// Good — allocate once with known capacity
items := make([]string, 0, len(data))
for _, v := range data {
    items = append(items, v)
}
```

### String Building

```go
// Avoid — each += allocates a new string
result := ""
for _, s := range parts {
    result += s
}

// Good — single allocation
var b strings.Builder
for _, s := range parts {
    b.WriteString(s)
}
result := b.String()
```

### Buffer Reuse

```go
// Avoid — allocates buffer every call
func readByte(r io.Reader) (byte, error) {
    var buf [1]byte
    _, err := r.Read(buf[:])
    return buf[0], err
}

// Good — caller provides reusable buffer
func readByte(r io.Reader, buf []byte) (byte, error) {
    _, err := r.Read(buf)
    return buf[0], err
}
```

### Buffered I/O

```go
// Avoid — each Read() call hits the OS
count := process(file)

// Good — bufio batches reads, dramatically fewer syscalls
br := bufio.NewReader(file)
count := process(br)
```

### sync.Pool for Frequent Allocations

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process() {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)
    // use buf...
}
```

CRITICAL: `sync.Pool` objects may be collected at any GC cycle. Never rely on pool for correctness — only for performance.

### Struct Field Alignment

```go
// Wastes memory — padding between fields
type Bad struct {
    a bool    // 1 byte + 7 padding
    b int64   // 8 bytes
    c bool    // 1 byte + 7 padding
}             // = 24 bytes

// Compact — fields ordered by size descending
type Good struct {
    b int64   // 8 bytes
    a bool    // 1 byte
    c bool    // 1 byte + 6 padding
}             // = 16 bytes
```

### Hot Path: Avoid Interface Boxing

```go
// Avoid in hot loops — each call boxes the int into interface{}
fmt.Sprintf("%d", n)

// Good — no interface boxing
strconv.Itoa(n)
```

## Profile-Guided Optimization (PGO)

Available since Go 1.21. Uses production CPU profiles to guide compiler optimizations (inlining, devirtualization). Typical improvement: 7-14% CPU reduction.

### PGO Workflow

1. Build and deploy WITHOUT PGO (baseline)
2. Collect a CPU profile from production (representative workload)
3. Save as `default.pgo` in the main package directory
4. Rebuild — the compiler auto-detects `default.pgo`
5. Deploy and measure improvement

```bash
# Collect production profile (30 seconds)
curl -o default.pgo 'http://localhost:6060/debug/pprof/profile?seconds=30'

# Rebuild with PGO (automatic — compiler finds default.pgo)
go build -o myapp ./cmd/myapp/
```

Use production profiles, NOT synthetic benchmarks. PGO optimizes the code paths that actually run in production.

## Runtime Tuning

### GOGC (Garbage Collection Target)

Controls GC frequency. Default: `GOGC=100` (GC runs when heap doubles).

- `GOGC=50` — GC runs more often, lower memory usage, higher CPU for GC
- `GOGC=200` — GC runs less often, higher memory usage, lower CPU for GC
- `GOGC=off` — Disable GC entirely (batch jobs that exit quickly)

### GOMEMLIMIT (Go 1.19+)

Soft memory limit. GC becomes more aggressive as heap approaches this limit.

```bash
GOMEMLIMIT=512MiB ./myapp
```

CRITICAL: This is a SOFT limit. It does not prevent OOM if live heap exceeds the limit. It tells the GC to work harder to stay under the target.

### Latency vs Throughput Trade-off

- **Latency-sensitive** (APIs): Lower GOGC (more frequent, shorter GC pauses)
- **Throughput-oriented** (batch): Higher GOGC or `GOGC=off` (minimize GC overhead)
- **Memory-constrained**: Set GOMEMLIMIT, let GC adapt automatically

## Execution Tracing

### When to Use

Use `runtime/trace` when profiling shows the code isn't CPU-bound but is still slow — indicates goroutine scheduling issues, GC pauses, or contention.

### Generating Traces

```bash
go test -trace=trace.out -bench=. -run=^$ ./pkg/
```

### Extracting Profiles from Traces

Traces can be converted to pprof profiles for text-based analysis:

```bash
go tool trace -pprof=net trace.out > trace-net.pprof      # Network blocking
go tool trace -pprof=sync trace.out > trace-sync.pprof    # Sync blocking
go tool trace -pprof=syscall trace.out > trace-syscall.pprof  # Syscall blocking
go tool trace -pprof=sched trace.out > trace-sched.pprof  # Scheduler latency
```

### Go 1.22+ Improvements

- 90% reduction in tracing overhead (1-2% vs previous 10-20%)
- Flight recorder mode — continuous recording with on-demand capture
- Safe for production use at low overhead

## OpenTelemetry for Go (Distributed Tracing)

When performance problems span multiple services, use OpenTelemetry for distributed tracing.

### Key Concepts

- **TracerProvider**: Creates tracers, manages span export
- **Span**: Unit of work with name, timing, attributes
- **Context propagation**: Carries trace IDs across service boundaries (HTTP headers)
- **OTLP**: Standard export protocol to backends (Jaeger, Tempo, Datadog)

### When to Use

- Request latency varies across services — need to find which service is slow
- Microservice architectures where a request touches multiple services
- Production latency investigation where local profiling isn't sufficient

OpenTelemetry complements local profiling: pprof finds hotspots within a service, OTel finds which service is the bottleneck.

## Continuous Profiling

For production systems, consider always-on profiling:

- **Grafana Pyroscope** (open source) — aggregates profiles over time, integrates with Grafana
- **Google Cloud Profiler** — <0.5% overhead, 30-day retention
- **Datadog Continuous Profiler** — integrates with PGO for automatic optimization

Continuous profiling catches performance regressions that only appear under production load patterns.

## Anti-Patterns

- Optimizing without profiling data — you WILL optimize the wrong thing
- Premature micro-optimization (removing interfaces, using `unsafe`) without measurement
- Ignoring allocations in hot loops — allocations are often the #1 bottleneck
- Using `interface{}` / `any` in performance-critical paths without benchmarking the cost
- Forgetting `-count` flag — a single benchmark run has no statistical validity
- Profiling debug builds instead of release builds
- Using synthetic workloads for PGO instead of production profiles
- Calling `runtime.ReadMemStats()` frequently — it triggers a stop-the-world pause

## Benchmarking Reminders

- Use `b.Loop()` (Go 1.24+) instead of `for i := 0; i < b.N; i++` — prevents compiler
  from optimizing away the benchmark target. For Go < 1.24, use a sink variable with `b.N`
- Use `b.ReportAllocs()` or `-benchmem` to track allocations per operation
- Use `-count=6` minimum for benchstat comparisons (more runs = better statistics)
- Use `b.StopTimer()`/`b.StartTimer()` to exclude setup from timing
- Use `benchstat old.bench new.bench` — check p-value < 0.05 for significance

## Quick Reference: Latency Numbers

Understanding relative costs helps prioritize optimizations:

| Operation | Latency | Relative |
|-----------|---------|----------|
| L1 cache reference | 0.5 ns | 1x |
| Main memory reference | 100 ns | 200x |
| SSD random read (NVMe) | 100 µs | 200,000x |
| HDD disk seek | 10 ms | 20,000,000x |
| Network round-trip (same datacenter) | 500 µs | 1,000,000x |
| Network round-trip (cross datacenter) | 150 ms | 300,000,000x |

Focus on I/O and allocation patterns first. Nanosecond-level CPU optimizations rarely matter unless you're in a tight inner loop processing millions of items.

## Cross-References

- → go-concurrency for sync.Pool hot-path patterns and goroutine scheduling
- → go-error-handling for error-path performance considerations
- → systematic-debugging for diagnosing performance regressions
- → go-testing for benchmark test patterns

<!-- cache:end -->

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
