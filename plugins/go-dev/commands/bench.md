---
argument-hint: "<file|function|package>"
description: "Generate and run Go benchmarks with profiling and optimization analysis"
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

**Usage:** `/bench <target>`

- `/bench pkg/auth/login.go` — benchmark all exported functions in a file
- `/bench ProcessOrder` — benchmark a specific function
- `/bench pkg/utils/` — benchmark all functions in a package

**Workflow:** detect tooling/existing benchmarks → analyze target → generate table-driven benchmarks → run with `-benchmem -count=6` → compare against baseline (if benchstat) → profile CPU + memory → summarize + suggest optimizations.

Ask: "What file, function, or package would you like me to benchmark?"

---

**If `$ARGUMENTS` is provided:**

Generate and run Go benchmarks for the specified code with statistical rigor.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "bench" "COMPLETE"; fi`

## Configuration

- **Target**: `$ARGUMENTS` (file, function, or package)

## Steps

### 1. Detect Benchmark Environment

```bash
which benchstat 2>/dev/null && echo "benchstat: available" || echo "benchstat: not found"
grep -rl 'func Bench' --include='*_test.go' ./path/to/package/
ls .bench-baseline*.txt 2>/dev/null
```

Also detect: existing `_test.go` patterns, testify vs stdlib, existing `.pprof` files.

If existing benchmarks for the target, ask via `AskUserQuestion`:

| Option | Action |
|--------|--------|
| Run existing | Run only, skip generation |
| Augment | Add new cases alongside existing |
| Generate fresh | Create new benchmarks in a separate file |

### 2. Analyze Target

Read the target and extract: function signatures, input types/sizes (for realistic data), dependencies/interfaces (for setup), I/O operations (special handling), allocation-heavy patterns (string concat, slice append, map ops), concurrency patterns (channels, mutexes).

For each function: classify CPU- vs memory- vs I/O-bound; identify variable-size sub-benchmarks; need for `b.ResetTimer()`; exported vs unexported (affects test package choice).

**I/O-bound functions:** warn the user — benchmark results will include I/O latency. Suggest mocking I/O for pure CPU/memory benchmarks, or proceed with I/O included if preferred.

### 3. Generate Benchmark Code

Table-driven, idiomatic:

```go
func BenchmarkFunctionName(b *testing.B) {
    benchmarks := []struct {
        name  string
        input InputType
    }{
        {"small input", smallInput},
        {"medium input", mediumInput},
        {"large input", largeInput},
    }

    for _, bm := range benchmarks {
        b.Run(bm.name, func(b *testing.B) {
            b.ReportAllocs()
            for i := 0; i < b.N; i++ {
                FunctionName(bm.input)
            }
        })
    }
}
```

Rules:

- `b.ReportAllocs()` in every sub-benchmark
- `b.ResetTimer()` after expensive setup
- `b.StopTimer()` / `b.StartTimer()` only when in-loop setup is unavoidable
- Prevent compiler optimization with a sink:
  ```go
  var sink ResultType
  for i := 0; i < b.N; i++ { sink = FunctionName(input) }
  _ = sink
  ```
- Sub-benchmarks for different input sizes
- Realistic test data, not trivial inputs
- Unexported functions → use the same package (not `_test` suffix)
- Exported functions → use `_test` suffix only when all parameter and return types are also exported

### 4. Run Benchmarks

```bash
go test -bench=. -benchmem -count=6 -run=^$ ./path/to/package/ 2>&1 | tee bench-results.txt
```

Flags: `-bench=.` (run all), `-benchmem` (allocations per op), `-count=6` (statistical significance for benchstat), `-run=^$` (skip unit tests), `-timeout 300s` if long-running.

If compile/run fails, fix the generated code and re-run.

### 5. Baseline Comparison

```bash
benchstat .bench-baseline.txt bench-results.txt   # if baseline exists
cp bench-results.txt .bench-baseline.txt          # if no baseline, save current
```

Present old vs new ns/op, B/op, allocs/op; p-value; delta %. If benchstat missing, note `go install golang.org/x/perf/cmd/benchstat@latest` for future runs.

### 6. CPU and Memory Profiling

```bash
go test -bench=. -cpuprofile=cpu.pprof -run=^$ ./path/to/package/
go test -bench=. -memprofile=mem.pprof -run=^$ ./path/to/package/

go tool pprof -top cpu.pprof 2>&1 | head -30
go tool pprof -top mem.pprof 2>&1 | head -30
go tool pprof -list=FunctionName cpu.pprof 2>&1
```

### 7. Analysis Report

```
## Benchmark Results

| Benchmark | ns/op | B/op | allocs/op |
|-----------|-------|------|-----------|

## Baseline Comparison
[benchstat output, or "No baseline — current saved"]

## CPU Hotspots
Top 5 functions by CPU time

## Memory Hotspots
Top 5 allocators

## Optimization Suggestions
[Concrete, actionable items based on profile data]

## Generated Files
- bench-results.txt — raw output
- .bench-baseline.txt — baseline for future comparisons
- cpu.pprof — CPU profile (`go tool pprof cpu.pprof`)
- mem.pprof — memory profile (`go tool pprof mem.pprof`)
```

**Common optimization patterns** (suggest based on profile data): `strings.Builder` over `+` concat; pre-allocated slices `make([]T, 0, cap)`; `sync.Pool` for frequently allocated objects; avoid interface boxing in hot paths; reuse buffers; `bytes.Buffer` pooling; struct field alignment for padding; `strconv` over `fmt.Sprintf` in hot paths.

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Benchmark file generated with table-driven benchmarks
2. Benchmark file compiles without errors
3. `go test -bench=. -benchmem -count=6` runs successfully
4. Benchmark results captured and summarized
5. CPU + memory profiles generated and analyzed
6. Optimization suggestions provided

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
