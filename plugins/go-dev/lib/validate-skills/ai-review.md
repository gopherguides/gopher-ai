# Validate-Skills — Step 6 AI Review

Loaded by `commands/validate-skills.md` Step 6. Reviews ALL extracted
code blocks (regardless of tier) for issues that static analysis cannot
catch.

Findings here are severity `info` or `warning` — never `error`.

## Cross-Platform Portability

| Pattern | Issue | Fix |
|---------|-------|-----|
| `mktemp /tmp/foo.XXXXXX.ext` | macOS requires template chars at end | `mktemp /tmp/foo-XXXXXX` then rename |
| `sed -i 's/...'` | No backup extension — fails on macOS | `sed -i.bak 's/...'` or `sed -i '' 's/...'` with platform check |
| `grep -P` | PCRE not available on macOS | Use `grep -E` (extended regex) |
| `readlink -f` | Not available on macOS | Use `realpath` or `cd "$(dirname ...)" && pwd` |
| `date -d '+1 hour'` | GNU date syntax, not macOS | Use `date -v+1H` on macOS or detect platform |
| `xargs -r` | `-r` is GNU extension | Pipe through `grep -v '^$'` before `xargs` |
| `tac` | Not available on macOS by default | Use `tail -r` or `sed '1!G;h;$!d'` |

## Common Shell Pitfalls

| Pattern | Issue | Fix |
|---------|-------|-----|
| `A && B \|\| C` | Not if/else — C runs if B fails too | `if A; then B; else C; fi` |
| `[ -z $VAR ]` | Breaks if VAR is empty or has spaces | `[ -z "$VAR" ]` |
| `for f in $(ls *.txt)` | Word splitting and glob issues | `for f in *.txt` |
| `echo $VAR` | Word splitting and glob expansion | `echo "$VAR"` |
| `cat file \| grep` | Useless use of cat | `grep pattern file` |

## Template Variable Consistency

For every `$VARIABLE` used in the block, confirm it is one of:

- Assigned earlier in the same block, OR
- A well-known environment variable (`$HOME`, `$PATH`, `$PWD`, `$USER`), OR
- A documented plugin variable (`$CLAUDE_PLUGIN_ROOT`, `$ARGUMENTS`, etc. — see `execution.md`)

Flag variables used but never defined — they may indicate a copy-paste error or missing context.

## External Tool Output Assumptions

Check whether the code:

- Assumes `curl` output is JSON without checking HTTP status?
- Pipes tool output directly to `jq` without error handling?
- Assumes `gh` / `git` / CLI tool output format without using `--json` or `--format`?
- Parses first-line output that might include version banners or progress text?

Each unsafe assumption is a `warning` finding.
