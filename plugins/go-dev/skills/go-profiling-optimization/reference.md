# Go Profiling & Optimization — Deep Reference

Loaded by `SKILL.md` when the agent needs pprof reading details, escape analysis,
runtime tuning, or distributed/continuous profiling guidance.

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
