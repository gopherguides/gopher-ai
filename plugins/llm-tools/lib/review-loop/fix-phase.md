# Review Loop — Fix Phase (Step 7)

Loaded by `commands/review-loop.md` Step 7. Owns the structured-vs-free-text
iteration, the parallel-dispatch agent prompt, and per-language test
generation conventions.

## Parallel Fix Dispatch (3+ findings, structured findings only)

When findings are structured JSON (Step 6a) and there are 3+ findings on
different files:

1. **Group by file** — same file = one subagent (sequential within file).
2. **Group by shared `_test.go`** — files in the same Go package may share
   `_test.go`, so they must be in the same group:
   ```bash
   # For each pair of source files, check if they're in the same package
   dirname "file1.go" == dirname "file2.go"
   ```
3. **Dispatch each file group** as an Agent subagent (sonnet) with this
   prompt:
   - "You are fixing review findings in `{FILE_PATH}`. Working directory:
     `{PROJECT_ROOT}`."
   - Include all findings for that file (title, body, line range, priority,
     category, confidence)
   - "For each finding: read the file, evaluate validity, fix if valid (skip
     if not), generate test if testable. Report STATUS (fixed/skipped),
     FILES_CHANGED, TEST_RESULTS, SKIPPED findings with reasons."
4. **Run all groups in parallel** with `run_in_background: true`.
5. **Collect results** — aggregate FIXED + SKIPPED counts; collect all files
   changed; collect all test results.
6. Proceed to Step 8 (Verify Phase) with combined results.

**Fall back to sequential** when:

- Fewer than 3 findings (subagent overhead not justified)
- Findings are free-text (not structured JSON — harder to distribute)
- All findings target the same file

## Structured Findings (codex exec mode) — Sequential

When findings are structured JSON from Step 6, iterate using `jq` and process
in priority order (P0 first):

```bash
for i in $(seq 0 $((FINDING_COUNT - 1))); do
  FILE=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].code_location.file_path")
  START=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].code_location.line_range.start")
  END=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].code_location.line_range.end")
  TITLE=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].title")
  BODY=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].body")
  PRIORITY=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].priority")
  CATEGORY=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].category")
  CONFIDENCE=$(printf '%s\n' "$FILTERED_JSON" | jq -r ".findings[$i].confidence_score")
done
```

For each finding:

1. Read `$FILE` lines `$START` to `$END` plus surrounding context
2. Evaluate: is this valid? Cross-reference with category and confidence.
3. **Auto-skip findings with `priority == 3` AND `confidence < 0.5`** (nit-level noise)
4. If valid: make the fix using the Edit tool
5. If not valid or intentionally skipped: record the reason
6. For testable fixes (changes observable behavior): generate a test (see
   "Test generation" below)

## Free-text Findings (codex quick / gemini / ollama)

For each finding from Step 6's free-text path:

1. Read the relevant file and surrounding code context
2. Evaluate the finding — is it valid and actionable?
3. If valid: make the fix using the Edit tool
4. If not valid or intentionally skipped: record the reason
5. For testable fixes: generate a test (see below)

Track counts: `FIXED`, `SKIPPED` (with reasons).

## Test Generation (both paths)

A fix is **testable** if it changes observable behavior (return values, errors,
side effects, HTTP responses). Skip cosmetic-only fixes (comments, formatting,
renames, log changes).

For each testable fix:

- **Go:** check for `*_test.go` in the same package; detect stdlib `testing` vs `testify`; if a table-driven test exists for the function, add a new case; otherwise create a new table-driven test. Verify: `go test ./path/to/package/... -run "TestFunctionName" -v`.
- **Node/TypeScript:** check `*.test.ts` / `*.spec.ts` / `__tests__/`; detect vitest vs jest vs mocha; follow describe/it patterns. Verify: `npx vitest run <test-file>` or `npx jest <test-file>`.
- **Rust:** check for `#[cfg(test)]` modules in the same file or `tests/`; detect built-in `#[test]` vs `rstest`. Verify: `cargo test <test-name>`.
- **Python:** check `test_*.py` / `*_test.py`; detect pytest vs unittest, parametrize patterns. Verify: `pytest <test-file> -v`.

If no test exists, create one following project conventions. Always verify
the new test passes before marking the fix complete.
