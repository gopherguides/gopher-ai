---
argument-hint: "[file|path] [--json]"
description: "Validate bash code blocks in markdown command and skill files"
allowed-tools: ["Bash", "Read", "Glob", "Grep", "AskUserQuestion"]
---

**If `$ARGUMENTS` is empty or not provided:**

Validate all bash/shell code blocks in plugin command and skill markdown files.

**Usage:** `/validate-skills [file|path] [--json]`

**Examples:**

- `/validate-skills` - Validate all plugin .md files
- `/validate-skills plugins/go-dev/commands/lint-fix.md` - Validate specific file
- `/validate-skills plugins/go-dev/commands/` - Validate all commands in a directory
- `/validate-skills --json` - Output structured JSON report

**Workflow:** discover → extract code blocks → 4-layer analysis (syntax, classification, safe execution, AI review) → report.

Proceed with validating all plugin markdown files.

---

**If `$ARGUMENTS` is provided:**

Validate bash/shell code blocks for the specified file, directory, or options.

## Configuration

Parse `$ARGUMENTS`:

- File path ending in `.md` → validate that single file
- Directory path → validate all `.md` files under it
- `--json` → output structured JSON instead of markdown report
- Default scope: `plugins/*/commands/*.md` and `plugins/*/skills/**/*.md`

Strip `--json` from arguments before parsing the path.

## Step 1: Discover Target Files

**Specific file:** verify it exists.

**Directory:**

```bash
find <directory> -name '*.md' -type f | sort
```

**Default (no path):**

```bash
find plugins/*/commands -name '*.md' -type f 2>/dev/null | sort
find plugins/*/skills -name '*.md' -type f 2>/dev/null | sort
```

Also include any `.md` files in `shared/commands/`. Report: "Found N markdown files to validate."

## Step 2: Extract Fenced Code Blocks

For each target file, extract all fenced code blocks tagged `bash`/`sh`/`shell`/`zsh`:

```bash
awk '
  /^[[:space:]]*```(bash|sh|shell|zsh)/ { in_block=1; start=NR+1; lang=$0; sub(/^[[:space:]]*```/, "", lang); next }
  /^[[:space:]]*```$/ && in_block { in_block=0; print start"-"NR-1" "lang; next }
  in_block { print NR": "$0 }
' <file>
```

Pattern matches indented blocks (list items, blockquotes). For each block record: file path (relative to project root), start/end line, language tag, code content. Write each to a temp file:

```bash
TMPDIR=`mktemp -d /tmp/validate-skills-XXXXXX`
```

Report: "Extracted N code blocks from M files."

## Step 3: Layer 1 — Static Analysis

For each block, dispatch by language tag:

- `bash`/`shell` → `bash -n "$TMPDIR/block-NNN.sh" 2>&1`
- `sh` → `sh -n` (POSIX mode)
- `zsh` → `zsh -n` if available, else skip with info note

Then run ShellCheck if available (skip on `zsh` — not supported). Suppressed: `SC1091` (sourced files), `SC2086` (quote variables — too noisy for examples), `SC2034` (unused vars — common in snippets).

```bash
shellcheck --format=json --shell=<bash|sh> \
  --exclude=SC1091 --exclude=SC2086 --exclude=SC2034 \
  "$TMPDIR/block-NNN.sh" 2>/dev/null
```

Map ShellCheck line numbers back to original markdown using each block's start-line offset.

If ShellCheck is missing: report "ShellCheck not installed — skipping SC analysis. Install with `brew install shellcheck`."

## Step 4: Layer 2 — Command Classification

Parse **ALL commands on each line** — including chained commands separated by `;`, `&&`, `||`, and pipe targets after `|`. A block's tier is the **highest (most restrictive) tier** of ANY command found anywhere in the block (RED > YELLOW > GREEN). This prevents destructive commands from hiding behind a GREEN prefix (e.g., `echo ok; rm -rf /`).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/classification.md` for the full GREEN / YELLOW / RED command tables. Each RED command found in a block emits a `warning` finding (not an error — may be intentional in documentation).

## Step 5: Layer 3 — Safe Execution (GREEN only)

Before executing, scan each block for **plugin runtime variables** that can't be resolved outside the plugin context. The literal list is:

```bash
grep -qE '\$\{?(CLAUDE_PLUGIN_ROOT|ARGUMENTS|MODEL|TARGET_PATH|STAGED|DRY_RUN|REVIEW_JSON|DIFF|FINDINGS|LLM_CHOICE)\}?' "$TMPDIR/block-NNN.sh"
```

Standard shell variables (`$HOME`, `$PATH`, `$PWD`, `$USER`, `$TMPDIR`) and locally-assigned variables are NOT runtime variables. If the block contains plugin runtime variables → skip execution; report `info` "Block contains plugin runtime variables — skipped execution."

For executable GREEN-tier blocks: detect timeout command (`gtimeout`/`timeout` — macOS lacks GNU `timeout`); skip with `info` note if neither is available. Then:

```bash
$TIMEOUT_CMD 5 env -i \
  HOME=/tmp \
  TMPDIR=/tmp \
  PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  <shell-command> "$TMPDIR/block-NNN.sh" 2>&1
```

`<shell-command>` is `bash --restricted` / `sh` / `zsh` based on the block's language tag (sh has no `--restricted` flag).

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/execution.md` for the full guardrails (timeout, restricted bash, clean env, write restriction) and the rationale for each.

**CRITICAL: Never execute YELLOW or RED blocks. Never execute blocks with unresolvable runtime variables.**

Non-zero exit codes become `warning` findings.

## Step 6: Layer 4 — AI Review

Review ALL extracted code blocks (regardless of tier) for issues that static analysis misses: cross-platform portability (macOS vs Linux), common shell pitfalls (`A && B || C`, unquoted vars), template-variable consistency, external-tool output assumptions.

→ Read `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/ai-review.md` for the full portability matrix (`mktemp`/`sed -i`/`grep -P`/`readlink -f`/`date -d`/`xargs -r`/`tac`) and the shell-pitfall table.

Present AI review findings with severity `info` or `warning`.

## Step 7: Generate Report

### Markdown Report (default)

```markdown
## Validation Report

**Files scanned:** N | **Code blocks found:** M | **Findings:** X errors, Y warnings, Z info

### Findings

| # | File | Lines | Severity | Layer | Finding | Suggested Fix |
|---|------|-------|----------|-------|---------|---------------|
| 1 | path/to/file.md | 45-52 | error | static | Syntax error: unexpected EOF | Close the if statement with `fi` |
| 2 | path/to/file.md | 78-85 | warning | classification | RED-tier command: `rm -rf` | Verify this is intentional |

### Summary by Layer

| Layer | Errors | Warnings | Info |
|-------|--------|----------|------|
| Static Analysis | N | N | N |
| Command Classification | N | N | N |
| Safe Execution | N | N | N |
| AI Review | N | N | N |
```

If no findings: "All N code blocks in M files passed validation."

Cleanup:

```bash
rm -rf "$TMPDIR"
```

### Structured Output (`--json`)

When `$ARGUMENTS` contains `--json`, strip the flag and after completing all steps, output **only** a JSON object — no markdown, no explanation:

```json
{
  "files_scanned": 0,
  "blocks_found": 0,
  "findings": [
    {
      "file": "string — file path relative to project root",
      "start_line": "number — start line in original markdown",
      "end_line": "number — end line in original markdown",
      "severity": "string — 'error', 'warning', or 'info'",
      "layer": "string — 'static', 'classification', 'execution', or 'review'",
      "finding": "string — description of the issue",
      "suggested_fix": "string — how to fix the issue"
    }
  ],
  "summary": {
    "errors": "number",
    "warnings": "number",
    "info": "number"
  }
}
```

> **Important:** In `--json` mode, do NOT emit the `<done>COMPLETE</done>` marker. The JSON output itself signals completion.

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. All target files discovered and scanned
2. All fenced bash/shell code blocks extracted with line numbers
3. Layer 1 (static analysis) ran on all blocks
4. Layer 2 (command classification) categorized all commands
5. Layer 3 (safe execution) ran on eligible GREEN-tier blocks
6. Layer 4 (AI review) reviewed all blocks
7. Findings report presented to the user

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.

## Further Reading

All siblings under `${CLAUDE_PLUGIN_ROOT}/lib/validate-skills/`:

- `classification.md` — full GREEN / YELLOW / RED command tables
- `execution.md` — Step 5 safe-execution guardrails (timeout, restricted bash, clean env, PATH, write restriction)
- `ai-review.md` — Step 6 cross-platform portability matrix + shell-pitfall table + tool-output assumption checks
