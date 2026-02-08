---
argument-hint: "<file|function|package>"
description: "Generate and run Go benchmarks with profiling and optimization analysis"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

**Usage:** `/bench <target>`

**Examples:**

- `/bench pkg/auth/login.go` - Benchmark all exported functions in a file
- `/bench ProcessOrder` - Benchmark a specific function
- `/bench pkg/utils/` - Benchmark all functions in a package

**Workflow:**

1. Detect benchmark environment (existing benchmarks, benchstat, pprof)
2. Analyze target functions for benchmark generation
3. Generate table-driven benchmark functions
4. Run benchmarks with `-benchmem -count=6`
5. Compare against baseline (if benchstat available)
6. Profile CPU and memory hotspots
7. Summarize results and suggest optimizations

Ask the user: "What file, function, or package would you like me to benchmark?"

---

**If `$ARGUMENTS` is provided:**

Generate and run Go benchmarks for the specified code. Produces table-driven benchmarks, runs them
with statistical rigor, profiles CPU and memory hotspots, and suggests concrete optimizations.

## Loop Initialization

Initialize persistent loop to ensure benchmarks are complete and analyzed:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "bench" "COMPLETE"`

## Configuration

- **Target**: `$ARGUMENTS` (file path, function name, or package)

## Steps

1. **Detect Benchmark Environment**

   Check available tooling and existing benchmarks:

   ```bash
   # Check for benchstat
   which benchstat 2>/dev/null && echo "benchstat: available" || echo "benchstat: not found"

   # Check for existing benchmark files in the target package
   grep -rl 'func Bench' --include='*_test.go' ./path/to/package/

   # Check for saved baseline results
   ls .bench-baseline*.txt 2>/dev/null
   ```

   Also detect:
   - Existing `_test.go` files in the target package for benchmark patterns already in use
   - Whether the project uses testify or standard testing
   - Any existing `.pprof` files or benchmark output files

   **If existing benchmarks found for the target**, ask the user:

   | Option | Action |
   |--------|--------|
   | Run existing | Run existing benchmarks only, skip generation |
   | Augment | Add new benchmark cases alongside existing ones |
   | Generate fresh | Create new benchmarks in a separate file |

2. **Analyze Target Code**

   Read the target file/function and extract:
   - Function signatures and parameters
   - Input types and sizes (to create realistic benchmark data)
   - Dependencies and interfaces (for benchmark setup)
   - I/O operations (network, disk) that may need special handling
   - Allocation-heavy patterns (string concatenation, slice appending, map operations)
   - Concurrency patterns (channels, mutexes) that affect benchmark design

   For each function identified, determine:
   - CPU-bound vs memory-bound vs I/O-bound behavior
   - Variable-size inputs for sub-benchmarks (e.g., `b.Run("size=100", ...)`)
   - Whether `b.ResetTimer()` is needed (for setup-heavy benchmarks)
   - Whether functions are exported or unexported (affects test package choice)

   **I/O-bound functions**: If the target performs network or disk I/O, warn the user that
   benchmark results will include I/O latency. Suggest mocking I/O dependencies for pure
   CPU/memory benchmarks, or proceed with I/O included if the user prefers.

3. **Generate Benchmark Code**

   Create table-driven benchmarks following Go idioms:

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

   Key generation rules:
   - Use `b.ReportAllocs()` in every sub-benchmark
   - Use `b.ResetTimer()` after expensive setup
   - Use `b.StopTimer()` / `b.StartTimer()` only when setup within the loop is unavoidable
   - Prevent compiler optimization with a sink variable:
     ```go
     var sink ResultType
     for i := 0; i < b.N; i++ {
         sink = FunctionName(input)
     }
     _ = sink
     ```
   - Include sub-benchmarks for different input sizes where applicable
   - Create realistic test data, not trivial inputs
   - For unexported functions, use the same package (not `_test` suffix)
   - For exported functions, prefer `_test` suffix package for realistic API testing

4. **Run Benchmarks**

   Execute with statistical rigor:

   ```bash
   go test -bench=. -benchmem -count=6 -run=^$ ./path/to/package/ 2>&1 | tee bench-results.txt
   ```

   Flags:
   - `-bench=.` — run all benchmarks
   - `-benchmem` — report memory allocations per operation
   - `-count=6` — run 6 times for statistical significance (benchstat needs multiple runs)
   - `-run=^$` — skip unit tests, only run benchmarks
   - `-timeout 300s` — add if benchmarks may be long-running

   If benchmarks fail to compile or run, fix the generated code and re-run.

5. **Baseline Comparison**

   If `benchstat` is available:

   ```bash
   # If a baseline file exists, compare
   benchstat .bench-baseline.txt bench-results.txt

   # If no baseline exists, save current results as baseline
   cp bench-results.txt .bench-baseline.txt
   ```

   Present benchstat output showing:
   - Old vs new ns/op, B/op, allocs/op
   - Statistical significance (p-value)
   - Delta percentages

   **If benchstat is not installed**, skip this step. Note in the output that `benchstat` can
   be installed with `go install golang.org/x/perf/cmd/benchstat@latest` for future comparisons.

6. **CPU and Memory Profiling**

   Generate profiles:

   ```bash
   # CPU profile
   go test -bench=. -cpuprofile=cpu.pprof -run=^$ ./path/to/package/

   # Memory profile
   go test -bench=. -memprofile=mem.pprof -run=^$ ./path/to/package/
   ```

   Analyze profiles:

   ```bash
   # CPU hotspots - top functions
   go tool pprof -top cpu.pprof 2>&1 | head -30

   # Memory hotspots - top allocators
   go tool pprof -top mem.pprof 2>&1 | head -30

   # Source-level view of hottest functions
   go tool pprof -list=FunctionName cpu.pprof 2>&1
   ```

7. **Analysis and Optimization Suggestions**

   Synthesize all collected data into a structured report:

   ```markdown
   ## Benchmark Results

   | Benchmark | ns/op | B/op | allocs/op |
   |-----------|-------|------|-----------|
   | BenchmarkX/small | 123 | 48 | 2 |
   | BenchmarkX/large | 4567 | 1024 | 15 |

   ## Baseline Comparison
   [benchstat output if available, or "No baseline — current results saved for future comparison"]

   ## CPU Hotspots
   Top 5 functions by CPU time with percentages

   ## Memory Hotspots
   Top 5 allocators with allocation counts and sizes

   ## Optimization Suggestions
   [Numbered list of concrete, actionable suggestions based on profile data]

   ## Generated Files
   - `bench-results.txt` — raw benchmark output
   - `.bench-baseline.txt` — baseline for future comparisons
   - `cpu.pprof` — CPU profile (`go tool pprof cpu.pprof`)
   - `mem.pprof` — memory profile (`go tool pprof mem.pprof`)
   ```

   Common optimization patterns to suggest based on profile data:
   - `strings.Builder` instead of `+` concatenation
   - Pre-allocated slices with `make([]T, 0, capacity)`
   - `sync.Pool` for frequently allocated objects
   - Avoiding interface boxing in hot paths
   - Reducing allocations by reusing buffers
   - Using `bytes.Buffer` pooling
   - Struct field alignment for reducing padding
   - Avoiding `fmt.Sprintf` in hot paths (use `strconv` directly)

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Benchmark file is generated with table-driven benchmark functions
2. Benchmark file compiles without errors
3. `go test -bench=. -benchmem -count=6` runs successfully
4. Benchmark results are captured and summarized
5. CPU and memory profiles are generated and analyzed
6. Optimization suggestions are provided based on profile data

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, benchmarks may be incomplete or failing.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
