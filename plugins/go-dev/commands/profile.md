---
argument-hint: "<file|function|package>"
description: "Profile Go code, identify bottlenecks, optimize, and verify improvements"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Agent", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

**Usage:** `/profile <target>`

**Examples:**

- `/profile ./pkg/auth/` - Profile all benchmarkable code in a package
- `/profile ProcessOrder` - Profile a specific function
- `/profile .` - Profile the current package

**Workflow:**

1. Establish baseline (run or generate benchmarks)
2. CPU profile — identify hot functions and lines
3. Memory profile — identify allocation hotspots and heap escapes
4. Trace analysis — goroutine scheduling and contention (if concurrent code)
5. Rank bottlenecks and isolate with targeted benchmarks
6. Optimize code and verify each change with benchstat
7. Final before/after comparison

Ask the user: "What file, function, or package would you like me to profile?"

---

**If `$ARGUMENTS` is provided:**

Profile Go code, identify performance bottlenecks, apply optimizations, and verify improvements
with statistical rigor. This follows a systematic profile → isolate → optimize → verify cycle.

## Loop Initialization

Initialize persistent loop to ensure profiling workflow completes:
!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "profile" "COMPLETE"; fi`

## Configuration

- **Target**: `$ARGUMENTS` (file path, function name, or package)

## IRON LAW: NEVER OPTIMIZE WITHOUT PROFILING DATA FIRST.

Do not guess. Do not "just try changing X." Every optimization must be preceded by profiling
data showing WHERE the bottleneck actually is. Measure before AND after every change.

## Phase 1: Environment & Baseline

1. **Check tooling availability:**

   ```bash
   which benchstat 2>/dev/null && echo "benchstat: available" || echo "benchstat: NOT FOUND"
   go version
   ```

   If `benchstat` is not installed, install it:
   ```bash
   go install golang.org/x/perf/cmd/benchstat@latest
   ```

2. **Locate and understand the target code:**

   - Read the target file(s)/package to understand what the code does
   - Identify the hot path: what functions do the main work?
   - Note any concurrency patterns (goroutines, channels, mutexes, sync.WaitGroup)
   - Note any I/O patterns (file reads, network calls, database queries)

3. **Find or create benchmarks:**

   ```bash
   # Check for existing benchmarks
   grep -rl 'func Bench' --include='*_test.go' ./target/path/ 2>/dev/null
   ```

   **If existing benchmarks found:** Use them. Run them to establish baseline.

   **If NO benchmarks found:** Generate benchmarks for the target functions. Follow the same
   patterns as `/bench` — table-driven, `b.ReportAllocs()`, realistic inputs, sink variables
   to prevent compiler elimination. For I/O-heavy functions, use `b.StopTimer()`/`b.StartTimer()`
   around setup.

4. **Establish baseline:**

   ```bash
   go test -bench=. -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-baseline.bench
   ```

   Run `benchstat` on the baseline to see variance:
   ```bash
   benchstat .profile-baseline.bench
   ```

   If variance is high (>5%), increase `-count` or investigate environment noise.

**HARD GATE: Do NOT proceed to Phase 2 until you have a working baseline with acceptable variance.**

## Phase 2: CPU Profiling

5. **Generate CPU profile:**

   ```bash
   go test -bench=. -cpuprofile=cpu.pprof -run=^$ ./target/path/
   ```

6. **Identify top CPU consumers (cumulative — this finds the real bottlenecks):**

   ```bash
   go tool pprof -top -cum cpu.pprof 2>&1 | head -25
   ```

   READ the output carefully:
   - **flat** = time spent ONLY in this function (not descendants)
   - **cum** = cumulative time (this function + everything it calls)
   - Sort by `cum` to find where time is actually being spent
   - The highest `cum%` functions are your primary targets

7. **Drill into the hottest functions with source annotations:**

   For each of the top 3 functions by cumulative time:

   ```bash
   go tool pprof -list=FunctionName cpu.pprof 2>&1
   ```

   READ the annotated source code:
   - Time values on the LEFT show how much time each LINE consumes
   - This tells you the EXACT lines that are hot
   - Look for: loops with per-iteration allocations, unbuffered I/O, string concatenation

8. **View callers and callees for context:**

   ```bash
   go tool pprof -peek=FunctionName cpu.pprof 2>&1
   ```

   This shows who calls the hot function and what it calls — helps understand the full path.

## Phase 3: Memory Profiling

9. **Generate memory profile:**

   ```bash
   go test -bench=. -memprofile=mem.pprof -run=^$ ./target/path/
   ```

10. **Identify top allocators:**

    ```bash
    go tool pprof -top -cum mem.pprof 2>&1 | head -25
    ```

    Look for functions with high allocation counts (allocs) and high allocation sizes (bytes).

11. **Drill into allocation sources:**

    For each of the top 3 allocating functions:

    ```bash
    go tool pprof -list=FunctionName mem.pprof 2>&1
    ```

    READ the annotated source — identify which lines are allocating and how much.

12. **Run escape analysis to understand heap vs stack:**

    ```bash
    go build -gcflags="-m" ./target/path/ 2>&1
    ```

    READ the output:
    - Lines saying `escapes to heap` indicate allocations that could potentially be optimized
    - Lines saying `does not escape` are already stack-allocated (good)
    - Lines saying `moved to heap` show variables the compiler couldn't keep on the stack
    - Common escape triggers: returning pointers, storing in interfaces, closure captures

    For more detailed output (shows inlining decisions too):
    ```bash
    go build -gcflags="-m -m" ./target/path/ 2>&1 | head -50
    ```

## Phase 4: Trace Analysis (Concurrent Code Only)

**Only run this phase if the target code uses goroutines, channels, mutexes, or sync primitives.**

13. **Check for concurrency patterns:**

    ```bash
    grep -n 'go func\|sync\.\|chan \|<-' ./target/path/*.go 2>/dev/null
    ```

    If no concurrency found, skip to Phase 5.

14. **Generate execution trace:**

    ```bash
    go test -trace=trace.out -run=^$ -bench=. ./target/path/
    ```

15. **Extract profiles from trace:**

    ```bash
    # Network blocking
    go tool trace -pprof=net trace.out > trace-net.pprof 2>/dev/null

    # Synchronization blocking (mutexes, channels)
    go tool trace -pprof=sync trace.out > trace-sync.pprof 2>/dev/null

    # Syscall blocking
    go tool trace -pprof=syscall trace.out > trace-syscall.pprof 2>/dev/null

    # Scheduler latency (time waiting to be scheduled)
    go tool trace -pprof=sched trace.out > trace-sched.pprof 2>/dev/null
    ```

16. **Analyze extracted trace profiles:**

    For each non-empty extracted profile:
    ```bash
    go tool pprof -top trace-sync.pprof 2>&1 | head -15
    ```

    Look for:
    - **sync blocking**: Lock contention — goroutines waiting on mutexes
    - **sched latency**: Too many goroutines saturating the scheduler
    - **net blocking**: Network I/O causing goroutines to block
    - **syscall blocking**: System calls holding goroutines

## Phase 5: Bottleneck Report & Isolation

17. **Synthesize all findings into a ranked bottleneck list:**

    Present a clear report:

    ```markdown
    ## Profiling Findings

    ### Bottleneck #1: [Description] (highest impact)
    - **Source**: file.go:line — [function name]
    - **Type**: CPU / Memory / Contention
    - **Evidence**: [what the profile showed — e.g., "42% of CPU time", "300K allocs/op"]
    - **Root cause**: [why it's slow — e.g., "per-byte reads from unbuffered reader"]
    - **Optimization**: [what to do — e.g., "wrap in bufio.NewReader()"]

    ### Bottleneck #2: ...
    ### Bottleneck #3: ...
    ```

18. **Ask the user before proceeding with optimizations:**

    Present the bottleneck report and ask:
    - "I found these bottlenecks. Should I proceed with optimizing them in order?"
    - "Any of these you want to skip or handle differently?"

19. **Create targeted isolation benchmarks** for each bottleneck (if not already covered by
    existing benchmarks). These should benchmark JUST the hot function so we can measure the
    specific improvement.

## Phase 6: Optimization (Iterative)

For each bottleneck, starting with highest impact:

20. **Save pre-optimization benchmark:**

    ```bash
    go test -bench=BenchmarkTarget -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-before.bench
    ```

21. **Apply the optimization.** Use `Edit` to modify the source code. Common patterns:

    | Bottleneck | Optimization |
    |-----------|-------------|
    | Unbuffered I/O reads | Wrap reader in `bufio.NewReader(rd)` |
    | String concatenation in loop | Use `[]rune` or `strings.Builder` |
    | Per-call buffer allocation | Accept reusable `[]byte` parameter |
    | Slice growing without capacity | `make([]T, 0, expectedCap)` |
    | `fmt.Sprintf` in hot path | Use `strconv` functions directly |
    | Interface boxing in hot path | Use concrete types |
    | Heap escapes from pointers | Return values instead of pointers for small structs |
    | Lock contention | Reduce critical section, use `sync.RWMutex`, shard data |
    | Goroutine overhead | Batch work per goroutine instead of one-per-item |
    | GC pressure from many small allocs | `sync.Pool` for frequently allocated objects |

22. **Verify tests still pass after optimization:**

    ```bash
    go test ./target/path/ -count=1
    ```

    If tests fail, fix the optimization before proceeding.

23. **Run post-optimization benchmark:**

    ```bash
    go test -bench=BenchmarkTarget -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-after.bench
    ```

24. **Compare with benchstat:**

    ```bash
    benchstat .profile-before.bench .profile-after.bench
    ```

    READ the output:
    - Check the **delta percentage** (e.g., `-99.97%` means 99.97% improvement)
    - Check the **p-value** (must be < 0.05 for statistical significance)
    - If p-value is >= 0.05, the improvement is not statistically significant — increase `-count`
      or the optimization may not be effective

25. **Present the results:**

    ```markdown
    ### Optimization: [what was changed]

    | Metric | Before | After | Change |
    |--------|--------|-------|--------|
    | ns/op | X | Y | -Z% |
    | B/op | X | Y | -Z% |
    | allocs/op | X | Y | -Z% |

    p-value: 0.000 (statistically significant)
    ```

26. **Re-profile to confirm the hotspot moved:**

    Run CPU and/or memory profiles again to verify the bottleneck is resolved and identify
    if a new bottleneck has emerged:

    ```bash
    go test -bench=. -cpuprofile=cpu-after.pprof -run=^$ ./target/path/
    go tool pprof -top -cum cpu-after.pprof 2>&1 | head -15
    ```

27. **Repeat for next bottleneck** or stop if:
    - Remaining bottlenecks show diminishing returns
    - The code is now I/O bound (network, disk) rather than CPU/memory bound
    - Further optimization would significantly increase code complexity

## Phase 7: Final Verification

28. **Run full benchmark suite against original baseline:**

    ```bash
    go test -bench=. -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-final.bench
    benchstat .profile-baseline.bench .profile-final.bench
    ```

29. **Confirm no regressions:**

    ```bash
    go test ./target/path/ -count=1
    ```

30. **Present final summary:**

    ```markdown
    ## Profiling & Optimization Summary

    ### Overall Improvement
    | Metric | Original | Optimized | Change |
    |--------|----------|-----------|--------|
    | ns/op | X | Y | -Z% |
    | B/op | X | Y | -Z% |
    | allocs/op | X | Y | -Z% |

    ### Optimizations Applied
    1. [Description] — [impact]
    2. [Description] — [impact]
    3. [Description] — [impact]

    ### Generated Files
    - `.profile-baseline.bench` — original baseline
    - `.profile-final.bench` — post-optimization results
    - `cpu.pprof` — CPU profile (`go tool pprof -http=:8080 cpu.pprof`)
    - `mem.pprof` — memory profile (`go tool pprof -http=:8080 mem.pprof`)
    ```

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Baseline benchmarks established with acceptable variance
2. CPU and memory profiles generated and analyzed
3. At least one bottleneck identified with profiling evidence
4. Bottleneck report presented to user
5. At least one optimization applied and verified with benchstat (p < 0.05)
6. Tests pass after all optimizations
7. Final before/after comparison presented

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, profiling may be incomplete.

---

**Safety notes:**
- If you've iterated 15+ times without success, document what's blocking and ask the user.
- Never expose `net/http/pprof` endpoints in production without authentication.
- Always run `go test` after each optimization to catch regressions immediately.
- If benchstat shows p >= 0.05, do not claim an improvement — it's not statistically significant.
