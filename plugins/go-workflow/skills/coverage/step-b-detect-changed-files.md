# Step B — Detect Changed Source Files

Loaded by `coverage-verification.md` Step B. This file owns the file-detection
plumbing: the `CHANGED_FILES` collector, per-language source-file filters, the
Go `get_pkg` comment-aware package extractor, and the gated/info partitioning.

## Collect changed files

Detect changed files including committed, uncommitted, staged, and untracked
files. Uncommitted/untracked changes are common when called from `/start-issue`
before the commit step:

```bash
mkdir -p .local/state
rm -f .local/state/coverage.out .local/state/coverage.json 2>/dev/null
CHANGED_FILES=$( (git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null; git diff --name-only HEAD 2>/dev/null; git diff --name-only --cached HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null) | sort -u )
```

The `rm -f` removes stale coverage artifacts from prior runs to prevent false
results if the current coverage command fails.

## Per-language source filters

Filter `CHANGED_FILES` to source files for the detected project type. Exclude
test files, generated files, and vendored code.

**Go** (`go.mod` exists):

```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.go$' \
  | grep -v '_test\.go$' \
  | grep -v '_templ\.go$' \
  | grep -v '_mock\.go$' \
  | grep -v '\.pb\.go$' \
  | grep -v '_gen\.go$' \
  | grep -v '^vendor/' \
  || true)
```

**Node/TypeScript** (`package.json` exists):

```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep -E '\.(ts|tsx|js|jsx)$' \
  | grep -v -E '\.(test|spec)\.' \
  | grep -v '^node_modules/' \
  | grep -v '^dist/' \
  || true)
```

**Rust** (`Cargo.toml` exists):

```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.rs$' \
  | grep -v -E '(^tests/|/tests/)' \
  || true)
```

**Python** (`pyproject.toml` or `setup.py` exists):

```bash
CHANGED_SRC=$(echo "$CHANGED_FILES" | grep '\.py$' \
  | grep -v -E '(^tests?/|/tests?/|test_[^/]*\.py$|_test\.py$|conftest\.py$)' \
  || true)
```

If `CHANGED_SRC` is empty → return empty to Step A's "no source files" skip
condition.

## Go: partition into gated vs info files

Then partition `CHANGED_SRC` into **gated** files (counted toward the aggregate
and the threshold) and **info** files (`package main` — shown in the report
but excluded from the gate):

```bash
# Comment-aware extractor: prints the actual Go package name (or empty).
# Strips //-line-comments and /*..*/ block comments (handling unterminated
# blocks across lines and inline blocks on the same line), then matches the
# first non-blank `^package <name>` line. This avoids false positives from
# `package main` text appearing inside doc comments.
get_pkg() {
  awk '
    BEGIN { in_block=0 }
    {
      line = $0
      if (in_block) { if (sub(/.*\*\//, "", line)) in_block=0; else next }
      # Strip block comments BEFORE line comments — otherwise a one-line
      # block comment containing a URL like `/* See https://example.com */`
      # has its `//` stripped first, leaving `/* See https:` and opening an
      # unterminated block that swallows the real package clause.
      while (match(line, /\/\*/)) {
        pre  = substr(line, 1, RSTART-1)
        rest = substr(line, RSTART+RLENGTH)
        if (match(rest, /\*\//)) {
          line = pre substr(rest, RSTART+RLENGTH)
        } else {
          line = pre; in_block = 1; break
        }
      }
      sub(/[[:space:]]*\/\/.*$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      if (line == "") next
      if (line ~ /^package[[:space:]]+[A-Za-z_]/) {
        split(line, a, /[[:space:]]+/); print a[2]; exit
      }
    }
  '
}

CHANGED_SRC_GATED=""
CHANGED_SRC_INFO=""
for f in $CHANGED_SRC; do
  # Detection is by the file's package clause, NOT filename. Any .go file
  # declaring `package main` (cmd/foo/main.go, cmd/foo/server.go, cmd/foo/wire.go,
  # internal/tools/run.go, ...) is excluded from the gate. For deleted files
  # (no longer on disk), read the blob from the base branch via `git show` so
  # a diff that deletes only `cmd/foo/main.go` still triggers the all-main
  # path in Step E.2 instead of producing a 0% gate prompt.
  if [ -f "$f" ]; then
    pkg=$(get_pkg < "$f" 2>/dev/null)
  else
    pkg=$(git show "${BASE_BRANCH}:${f}" 2>/dev/null | get_pkg)
  fi
  if [ "$pkg" = "main" ]; then
    CHANGED_SRC_INFO="${CHANGED_SRC_INFO}${f}
"
  else
    CHANGED_SRC_GATED="${CHANGED_SRC_GATED}${f}
"
  fi
done
CHANGED_SRC_GATED=$(printf '%s' "$CHANGED_SRC_GATED" | sed '/^$/d')
CHANGED_SRC_INFO=$(printf '%s'  "$CHANGED_SRC_INFO"  | sed '/^$/d')
```

## Why exclude `package main`?

Idiomatic Go keeps `func main()` to a thin shim — argument parsing, dependency
wiring, and a call into a testable package. There's little to assert against,
and what's left (e.g. `os.Exit` paths) is awkward to test without refactoring
purely to satisfy the metric. This is a **`package main`-only** carve-out —
touching a hard-to-test middleware or handler file still trips the gate (the
"if you touch it, you own it" rule is unchanged). See [#143](https://github.com/gopherguides/gopher-ai/issues/143)
for full rationale and external references.
