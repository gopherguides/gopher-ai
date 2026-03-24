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

**Workflow:**

1. Extract fenced bash/shell code blocks with line numbers
2. Run static analysis (bash -n, shellcheck)
3. Classify commands into safety tiers (GREEN/YELLOW/RED)
4. Safely execute GREEN-tier commands
5. AI review for portability and correctness
6. Present structured findings report

Proceed with validating all plugin markdown files.

---

**If `$ARGUMENTS` is provided:**

Validate bash/shell code blocks for the specified file, directory, or options.

## Configuration

Parse `$ARGUMENTS`:

- If argument is a file path (ends in `.md`): validate that single file
- If argument is a directory path: validate all `.md` files under it
- `--json`: Output structured JSON instead of markdown report
- Default scope (no path): `plugins/*/commands/*.md` and `plugins/*/skills/**/*.md`

Strip `--json` from arguments before parsing the path.

## Step 1: Discover Target Files

Find all markdown files to validate based on the parsed scope:

**If a specific file was given:**

Verify it exists and use it as the sole target.

**If a directory was given:**

```bash
find <directory> -name '*.md' -type f | sort
```

**If no path given (default):**

```bash
find plugins/*/commands -name '*.md' -type f 2>/dev/null | sort
find plugins/*/skills -name '*.md' -type f 2>/dev/null | sort
```

Also include any `.md` files in the `shared/commands/` directory.

Report the count: "Found N markdown files to validate."

## Step 2: Extract Fenced Code Blocks

For each target file, extract all fenced code blocks tagged as `bash`, `sh`, `shell`, or `zsh`.

Use `awk` to parse the markdown:

```bash
awk '
  /^[[:space:]]*```(bash|sh|shell|zsh)/ { in_block=1; start=NR+1; lang=$0; sub(/^[[:space:]]*```/, "", lang); next }
  /^[[:space:]]*```$/ && in_block { in_block=0; print start"-"NR-1" "lang; next }
  in_block { print NR": "$0 }
' <file>
```

**Note:** The pattern matches fenced blocks with optional leading whitespace (indented blocks inside list items, blockquotes, etc.).

For each block, record:
- **File path** (relative to project root)
- **Start line** and **end line** in the original markdown
- **Language tag** (bash, sh, shell, zsh)
- **Code content** (the lines between the fences)

Write each extracted block to a temporary file for analysis:

```bash
TMPDIR=`mktemp -d /tmp/validate-skills-XXXXXX`
```

Report: "Extracted N code blocks from M files."

## Step 3: Layer 1 — Static Analysis

### 3a. Syntax Check

For each extracted code block, dispatch by language tag:

- `bash` or `shell` → `bash -n "$TMPDIR/block-NNN.sh" 2>&1`
- `sh` → `sh -n "$TMPDIR/block-NNN.sh" 2>&1` (POSIX mode)
- `zsh` → `zsh -n "$TMPDIR/block-NNN.sh" 2>&1` (if `zsh` is available, otherwise skip with info note)

Record any syntax errors with the original file path and line offset.

### 3b. ShellCheck Analysis

Check if ShellCheck is available:

```bash
command -v shellcheck >/dev/null 2>&1 && echo "available" || echo "not available"
```

**If ShellCheck is available**, run it on each block with the appropriate shell dialect:

- `bash` or `shell` → `--shell=bash`
- `sh` → `--shell=sh`
- `zsh` → skip ShellCheck (not supported by ShellCheck)

```bash
shellcheck --format=json --shell=<detected-shell> \
  --exclude=SC1091 \
  --exclude=SC2086 \
  --exclude=SC2034 \
  "$TMPDIR/block-NNN.sh" 2>/dev/null
```

Suppressions:
- `SC1091`: Can't follow non-constant source (sourced files unavailable)
- `SC2086`: Double quote to prevent globbing and word splitting (too noisy for inline examples)
- `SC2034`: Variable appears unused (common in example snippets)

Parse the JSON output. Map ShellCheck line numbers back to original markdown line numbers using the block's start line offset.

**If ShellCheck is not available**, report: "ShellCheck not installed — skipping SC analysis. Install with `brew install shellcheck` for deeper analysis."

## Step 4: Layer 2 — Command Classification

For each code block, parse **ALL commands on each line** — including chained commands separated by `;`, `&&`, `||`, and pipe targets after `|`. A block's tier is the **highest (most restrictive) tier** of ANY command found anywhere in the block (RED > YELLOW > GREEN). This prevents destructive commands from hiding behind a GREEN prefix (e.g., `echo ok; rm -rf /`).

### GREEN (read-only, safe to execute)

`echo`, `cat`, `grep`, `rg`, `jq`, `mktemp`, `ls`, `pwd`, `date`, `command`, `basename`, `dirname`, `wc`, `sort`, `head`, `tail`, `tr`, `cut`, `sed` (without `-i`), `printf`, `test`, `[`, `true`, `false`, `type`, `which`, `readlink`, `realpath`, `stat`, `file`, `diff`, `comm`, `uniq`, `export`

### YELLOW (conditionally safe, syntax check only)

`awk`, `env`, `tee`, `find` (without `-exec`, `-delete`, `-execdir`), `git log`, `git status`, `git diff`, `git branch`, `git show`, `git rev-parse`, `git remote`, `curl` (without pipe to `sh`/`bash`/`eval`), `wget` (without pipe to `sh`/`bash`/`eval`), `go build`, `go vet`, `go test`, `go list`, `go mod`, `go version`, `golangci-lint`, `npm`, `npx`, `node`, `docker`, `gh`

**Note:** `awk`, `env`, and `tee` are YELLOW because they can execute arbitrary subprocesses (`awk 'BEGIN{system(...)}'`, `env bash -c '...'`) or write to arbitrary files.

### RED (never execute, report as warning)

`rm`, `rmdir`, `dd`, `sudo`, `eval`, `exec`, `kill`, `killall`, `mkfs`, `mount`, `umount`, `chmod`, `chown`, `git push`, `git reset --hard`, `git clean`, `git checkout .`, `git restore .`, `curl | sh`, `curl | bash`, `wget | sh`, `wget | bash`, any pipe to `sh`, `bash`, `eval`, or `exec`

For each RED-tier command found, emit a **warning** finding (not an error — these may be intentional in documentation or guarded contexts).

## Step 5: Layer 3 — Safe Execution (GREEN Commands Only)

### 5a. Detect Template Variables

Before executing a block, scan for **known plugin runtime variables** that cannot be resolved outside the plugin context. Use an explicit list — do NOT match all uppercase variables, as that would falsely flag standard shell variables like `$HOME`, `$PATH`, `$PWD`.

Known plugin runtime variables (match these literally):

```
$CLAUDE_PLUGIN_ROOT, ${CLAUDE_PLUGIN_ROOT}
$ARGUMENTS, ${ARGUMENTS}
$MODEL, ${MODEL}
$TARGET_PATH, ${TARGET_PATH}
$STAGED, ${STAGED}
$DRY_RUN, ${DRY_RUN}
$REVIEW_JSON, ${REVIEW_JSON}
$DIFF, ${DIFF}
$FINDINGS, ${FINDINGS}
$LLM_CHOICE, ${LLM_CHOICE}
```

```bash
grep -qE '\$\{?(CLAUDE_PLUGIN_ROOT|ARGUMENTS|MODEL|TARGET_PATH|STAGED|DRY_RUN|REVIEW_JSON|DIFF|FINDINGS|LLM_CHOICE)\}?' "$TMPDIR/block-NNN.sh"
```

Standard shell variables (`$HOME`, `$PATH`, `$PWD`, `$USER`, `$TMPDIR`) and variables assigned within the block itself are NOT considered template variables.

**If plugin runtime variables found**: Skip execution for this block. Report as `info`: "Block contains plugin runtime variables — skipped execution."

### 5b. Execute GREEN Blocks

For blocks containing only GREEN-tier commands and no unresolvable template variables:

Detect the timeout command (macOS does not ship GNU `timeout`):

```bash
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
else
  TIMEOUT_CMD=""
fi
```

If no timeout command is available, skip execution and report as `info`: "No `timeout` or `gtimeout` available — skipping safe execution. Install coreutils for execution support."

Execute with the detected timeout command, dispatching by the block's language tag:

- `bash` or `shell` → `bash --restricted`
- `sh` → `sh` (POSIX mode, no `--restricted` flag — not supported by POSIX sh)
- `zsh` → `zsh` (if available, otherwise skip with info note)

```bash
$TIMEOUT_CMD 5 env -i \
  HOME=/tmp \
  TMPDIR=/tmp \
  PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  <shell-command> "$TMPDIR/block-NNN.sh" 2>&1
```

Where `<shell-command>` is `bash --restricted`, `sh`, or `zsh` based on the block's language tag.

Guardrails:
- **Timeout**: 5 seconds per block (via `gtimeout` on macOS, `timeout` on Linux)
- **Restricted bash** (`bash --restricted`): Prevents `cd`, changing `PATH`, redirecting output to files outside `/tmp`
- **Clean environment** (`env -i`): No inherited secrets or config
- **PATH includes `/opt/homebrew/bin`**: Ensures tools installed via Homebrew on Apple Silicon are available
- **Write restriction**: Only `/tmp` is writable

Record exit code and any stderr output. Non-zero exit codes become `warning` findings.

**CRITICAL: Never execute blocks classified as YELLOW or RED. Never execute blocks with unresolvable template variables.**

## Step 6: Layer 4 — AI Review

Review ALL extracted code blocks (regardless of tier) for issues that static analysis cannot catch:

### Cross-Platform Portability

Check for macOS vs Linux incompatibilities:

| Pattern | Issue | Fix |
|---------|-------|-----|
| `mktemp /tmp/foo.XXXXXX.ext` | macOS requires template chars at end | `mktemp /tmp/foo-XXXXXX` then rename |
| `sed -i 's/...'` | No backup extension — fails on macOS | `sed -i.bak 's/...'` or `sed -i '' 's/...'` with platform check |
| `grep -P` | PCRE not available on macOS | Use `grep -E` (extended regex) |
| `readlink -f` | Not available on macOS | Use `realpath` or `cd "$(dirname ...)" && pwd` |
| `date -d '+1 hour'` | GNU date syntax, not macOS | Use `date -v+1H` on macOS or detect platform |
| `xargs -r` | `-r` is GNU extension | Pipe through `grep -v '^$'` before `xargs` |
| `tac` | Not available on macOS by default | Use `tail -r` or `sed '1!G;h;$!d'` |

### Common Shell Pitfalls

| Pattern | Issue | Fix |
|---------|-------|-----|
| `A && B \|\| C` | Not if/else — C runs if B fails too | Use `if A; then B; else C; fi` |
| `[ -z $VAR ]` | Breaks if VAR is empty or has spaces | `[ -z "$VAR" ]` |
| `for f in $(ls *.txt)` | Word splitting and glob issues | `for f in *.txt` |
| `echo $VAR` | Word splitting and glob expansion | `echo "$VAR"` |
| `cat file \| grep` | Useless use of cat | `grep pattern file` |

### Template Variable Consistency

- Is every `$VARIABLE` used in the block either:
  - Assigned earlier in the same block, OR
  - A well-known environment variable (`$HOME`, `$PATH`, `$PWD`, `$USER`), OR
  - A documented plugin variable (`$CLAUDE_PLUGIN_ROOT`, `$ARGUMENTS`)
- Flag variables used but never defined (may indicate a copy-paste error or missing context)

### External Tool Output Assumptions

- Does the code assume `curl` output is JSON without checking HTTP status?
- Does the code pipe tool output directly to `jq` without error handling?
- Does the code assume `gh` / `git` / CLI tool output format without using `--json` or `--format`?
- Does the code parse first-line output that might include version banners or progress text?

Present AI review findings with severity `info` or `warning`.

## Step 7: Generate Report

### Markdown Report (default)

Present all findings in a structured table:

```markdown
## Validation Report

**Files scanned:** N | **Code blocks found:** M | **Findings:** X errors, Y warnings, Z info

### Findings

| # | File | Lines | Severity | Layer | Finding | Suggested Fix |
|---|------|-------|----------|-------|---------|---------------|
| 1 | path/to/file.md | 45-52 | error | static | Syntax error: unexpected EOF | Close the if statement with `fi` |
| 2 | path/to/file.md | 78-85 | warning | classification | RED-tier command: `rm -rf` | Verify this is intentional |
| 3 | path/to/file.md | 102-110 | warning | review | `mktemp` template not portable | Use `mktemp /tmp/prefix-XXXXXX` |

### Summary by Layer

| Layer | Errors | Warnings | Info |
|-------|--------|----------|------|
| Static Analysis | N | N | N |
| Command Classification | N | N | N |
| Safe Execution | N | N | N |
| AI Review | N | N | N |
```

If no findings: "All N code blocks in M files passed validation."

### Cleanup

```bash
rm -rf "$TMPDIR"
```

---

## Structured Output (`--json`)

When `$ARGUMENTS` contains `--json`, strip the flag from other arguments and after completing all steps, output **only** a JSON object (no markdown, no explanation) matching this schema:

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
    "errors": "number — total errors",
    "warnings": "number — total warnings",
    "info": "number — total info findings"
  }
}
```

Strip the `--json` flag from `$ARGUMENTS` before parsing path and options.

> **Important:** When using `--json` mode, do NOT emit the `<done>COMPLETE</done>` marker. The JSON output itself signals completion.

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All target files have been discovered and scanned
2. All fenced bash/shell code blocks have been extracted with line numbers
3. Layer 1 (static analysis) has run on all blocks
4. Layer 2 (command classification) has categorized all commands
5. Layer 3 (safe execution) has run on eligible GREEN-tier blocks
6. Layer 4 (AI review) has reviewed all blocks
7. The findings report has been presented to the user

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
