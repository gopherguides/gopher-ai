# Go Profiling — Worked Examples

Loaded by `SKILL.md` when the agent is doing PGO setup or trace-based diagnosis.

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
