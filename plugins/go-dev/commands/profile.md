---
argument-hint: "<file|function|package>"
description: "Profile Go code, identify bottlenecks, optimize, and verify improvements"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "Agent", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

**Usage:** `/profile <target>`

**Examples:**
- `/profile ./pkg/auth/` — profile all benchmarkable code in a package
- `/profile ProcessOrder` — profile a specific function
- `/profile .` — profile the current package

**Workflow:** baseline → CPU profile → memory profile → trace (if concurrent) → rank bottlenecks → optimize one at a time and verify with benchstat → final before/after comparison.

Ask: "What file, function, or package would you like me to profile?"

---

**If `$ARGUMENTS` is provided:**

Profile Go code, identify bottlenecks, apply optimizations, and verify improvements with statistical rigor. Systematic profile → isolate → optimize → verify cycle.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "profile" "COMPLETE"; fi`

## Configuration

- **Target**: `$ARGUMENTS` (file, function, or package)

## IRON LAW: NEVER OPTIMIZE WITHOUT PROFILING DATA FIRST

Do not guess. Do not "just try changing X." Every optimization must be preceded by profiling data showing WHERE the bottleneck actually is. Measure before AND after every change.

## Phase 1: Environment & Baseline

1. **Check tooling:**
   ```bash
   which benchstat 2>/dev/null && echo "benchstat: available" || echo "benchstat: NOT FOUND"
   go version
   ```
   Install benchstat if missing: `go install golang.org/x/perf/cmd/benchstat@latest`

2. **Locate target code** — read it, identify hot path, note concurrency and I/O patterns.

3. **Find or create benchmarks:**
   ```bash
   rg -l 'func Bench' --glob '*_test.go' ./target/path/ 2>/dev/null
   ```
   If none found: generate table-driven benchmarks with `b.ReportAllocs()`, realistic inputs, sink variables, `b.StopTimer()`/`b.StartTimer()` around setup. Follow the `/bench` patterns.

4. **Establish baseline:**
   ```bash
   go test -bench=. -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-baseline.bench
   benchstat .profile-baseline.bench
   ```
   If variance >5%, increase `-count` or investigate environment noise.

**HARD GATE:** Do NOT proceed to Phase 2 until you have a working baseline with acceptable variance.

## Phases 2–4: Profiling

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/profile/phases.md` for the full procedure:

- **Phase 2 — CPU profiling:** `go test -cpuprofile`, `go tool pprof -top -cum`, source annotations via `-list=Function`, callers/callees via `-peek=Function`
- **Phase 3 — memory profiling:** `-memprofile`, `-top -cum`, `-list=Function`, escape analysis via `go build -gcflags="-m"`
- **Phase 4 — trace analysis (concurrent code only):** detect via `rg -n 'go func|sync\\.|chan |<-'`; generate `-trace=trace.out`; extract `net`, `sync`, `syscall`, `sched` profiles via `go tool trace -pprof`

## Phase 5: Bottleneck Report & Isolation

Synthesize findings into a ranked list:

```markdown
## Profiling Findings

### Bottleneck #1: [Description] (highest impact)
- **Source**: file.go:line — [function name]
- **Type**: CPU / Memory / Contention
- **Evidence**: [what the profile showed — e.g., "42% of CPU time", "300K allocs/op"]
- **Root cause**: [why it's slow]
- **Optimization**: [what to do]

### Bottleneck #2: …
### Bottleneck #3: …
```

Ask the user: "I found these bottlenecks. Should I proceed with optimizing them in order? Any to skip?"

Create targeted **isolation benchmarks** for each bottleneck (if not already covered) — benchmark JUST the hot function so we can measure the specific improvement.

## Phase 6: Optimization (iterative, one bottleneck at a time)

For each bottleneck (highest impact first):

1. Save pre-optimization benchmark to `.profile-before.bench`
2. Apply the optimization (see the patterns table in `lib/profile/phases.md`)
3. `go test ./target/path/ -count=1` — fix any regressions before proceeding
4. Save post-optimization benchmark to `.profile-after.bench`
5. `benchstat .profile-before.bench .profile-after.bench` — verify p-value < 0.05 (statistically significant)
6. Re-profile to confirm the hotspot moved (a new bottleneck may have emerged)
7. Repeat for next bottleneck OR stop if diminishing returns / I/O-bound / further optimization adds significant complexity

## Phase 7: Final Verification

```bash
go test -bench=. -benchmem -count=6 -run=^$ ./target/path/ 2>&1 | tee .profile-final.bench
benchstat .profile-baseline.bench .profile-final.bench
go test ./target/path/ -count=1
```

Present a final summary with overall improvement table and the list of optimizations applied. Generated files: `.profile-baseline.bench`, `.profile-final.bench`, `cpu.pprof`, `mem.pprof` (interactive view: `go tool pprof -http=:8080 cpu.pprof`).

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Baseline benchmarks established with acceptable variance
2. CPU and memory profiles generated and analyzed
3. Bottleneck report presented (may be empty if already optimal)
4. If bottlenecks found: optimizations applied and verified with benchstat, OR user declined
5. If no bottlenecks found: report that the code is already well-optimized with profiling evidence
6. Tests pass (if optimizations were applied)
7. Final summary presented

```
<done>COMPLETE</done>
```

**Safety:**
- If 15+ iterations without success, document blockers and ask the user
- Never expose `net/http/pprof` endpoints in production without authentication
- Always run `go test` after each optimization
- If benchstat shows p ≥ 0.05, do not claim improvement — it's not statistically significant

## Further Reading

- `${CLAUDE_PLUGIN_ROOT}/lib/profile/phases.md` — Phase 2 (CPU profiling), Phase 3 (memory + escape analysis), Phase 4 (trace analysis), Phase 6 optimization-pattern table
