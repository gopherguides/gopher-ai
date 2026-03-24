---
name: validate-skills
description: |
  WHEN: User is editing .md files in commands/ or skills/ directories, creating new slash commands
  or skills, modifying fenced bash/shell code blocks in markdown plugin files, asking about
  validating command files, or discussing shell code correctness in plugin markdown.
  Also activate when user mentions "shellcheck", "bash -n", "code block validation",
  "portability check", or has just finished writing/editing a command or skill markdown file.
  WHEN NOT: Editing Go source code, working with non-markdown files, writing general
  documentation or README files, questions unrelated to plugin command/skill development
---

# Validate Skills

When working on `.md` command or skill files that contain fenced bash/shell code blocks, suggest running `/validate-skills` to catch issues before they ship.

## What It Catches

- **Syntax errors**: Unclosed quotes, mismatched if/fi, invalid redirections (`bash -n`)
- **Shell pitfalls**: Unquoted variables, deprecated syntax, SC2015 `A && B || C` (`shellcheck`)
- **Portability issues**: macOS vs Linux differences (`mktemp` templates, `sed -i`, `grep -P`, `readlink -f`, `date` flags)
- **Unsafe commands**: RED-tier commands (`rm`, `sudo`, `eval`, pipe-to-shell) flagged as warnings
- **Template variable handling**: Blocks with unresolvable plugin variables (`$CLAUDE_PLUGIN_ROOT`, `$ARGUMENTS`, `$MODEL`) are skipped for execution but still syntax-checked
- **Execution failures**: GREEN-tier read-only commands that fail at runtime (broken `jq` filters, invalid `grep` patterns, `mktemp` template errors)

## Common Pitfalls in Plugin Markdown

### macOS vs Linux
- `mktemp /tmp/foo.XXXXXX.md` — template characters must be at end on macOS, use `mktemp /tmp/foo-XXXXXX` + rename
- `sed -i '' 's/old/new/' file` (macOS) vs `sed -i 's/old/new/' file` (Linux) — use `sed -i.bak` for portability
- `grep -P` not available on macOS — use `grep -E` instead
- `readlink -f` not available on macOS — use `realpath` or `cd ... && pwd`
- `date -d` (Linux) vs `date -j -f` (macOS)

### Shell Safety
- `A && B || C` is NOT if/else — if B fails, C still runs (ShellCheck SC2015)
- Unquoted `$VAR` splits on whitespace and expands globs — always quote: `"$VAR"`
- `[ -z $VAR ]` fails if VAR is empty — use `[ -z "$VAR" ]`

### External Tool Output
- Never assume tool output is pure JSON — check for banners, headers, progress bars
- `curl` may return HTML error pages on failure — check HTTP status codes
- `gh` CLI output format changes between versions — prefer `--json` + `--jq`

## Usage

```
/validate-skills                              # Validate all plugin .md files
/validate-skills plugins/go-dev/commands/     # Validate a directory
/validate-skills path/to/command.md           # Validate a specific file
/validate-skills --json                       # Output structured JSON
```
