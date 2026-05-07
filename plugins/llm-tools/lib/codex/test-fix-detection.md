# Codex — Review-Fix Detection

Loaded by `commands/codex.md` Step 2 when the prompt looks like it's
addressing review feedback. Three pieces:

1. **Baseline capture** — hash every `_test.go` before running Codex
2. **Prompt injection** (Exec + Review-with-context paths) — append a test-generation requirement to the Codex prompt
3. **Post-run fallback** — diff the hashes; if no test files changed and the fix touched testable behavior, Claude generates the missing tests

Native `codex review --uncommitted/--base/--commit` doesn't accept custom
prompts, so the post-run fallback is the only safety net for that path.

## Baseline (run BEFORE Codex)

```bash
# Record current test file content hashes for comparison after Codex completes.
# This detects both new files AND modifications to existing test files.
# Uses find -exec for safe handling of paths with spaces.
TEST_BASELINE=$(mktemp)
find . -name '*_test.go' -type f -exec sh -c '
  for f; do md5sum "$f" 2>/dev/null || md5 -r "$f" 2>/dev/null; done
' _ {} + | sort > "$TEST_BASELINE"
```

## Prompt injection (Exec Flow + Review Flow with PR/issue context)

Append this block to the Codex prompt:

```text

---

## Test Generation Requirement

For every testable fix you make, write a corresponding test. A fix is testable if it changes observable behavior (return values, errors, side effects, HTTP responses). Skip tests for cosmetic changes (comments, formatting, renames, log changes).

- Check for existing `_test.go` files and table-driven tests for affected functions
- If a table-driven test exists, add a new case covering the fixed behavior
- If no test exists, create a new table-driven test
- Follow the existing test conventions in the package (testify vs stdlib, naming patterns)
- Verify all new tests pass
```

## Post-run fallback

After Codex completes (either flow), check if any `_test.go` files were created or modified by comparing content hashes:

```bash
TEST_CURRENT=$(mktemp)
find . -name '*_test.go' -type f -exec sh -c '
  for f; do md5sum "$f" 2>/dev/null || md5 -r "$f" 2>/dev/null; done
' _ {} + | sort > "$TEST_CURRENT"

# Find lines only in current (new or modified files), excluding deletions.
# comm -13 shows lines in file2 not in file1 (new/changed hashes).
CHANGED_TESTS=$(comm -13 "$TEST_BASELINE" "$TEST_CURRENT" | awk '{print $NF}' | sort -u)
rm -f "$TEST_BASELINE" "$TEST_CURRENT"

if [ -n "$CHANGED_TESTS" ]; then
  echo "Test files created or modified by Codex: $CHANGED_TESTS"
else
  echo "No test file changes from Codex"
fi
```

If no test files were created or modified by this Codex run AND the fix
modified testable behavior, Claude generates the missing tests following the
same guidelines as the prompt-injection block above.
