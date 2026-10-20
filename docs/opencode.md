# OpenCode

gopher-ai supports OpenCode v2. `scripts/build-universal.sh` produces
`dist/opencode/` and the `gopher-ai-opencode-v<version>.tar.gz` release
archive, and `scripts/install-opencode.sh` installs it. `scripts/install-all.sh`
runs that installer whenever `opencode` is on `PATH`.

## Install

```bash
./scripts/build-universal.sh
./scripts/install-opencode.sh             # install or update
./scripts/install-opencode.sh --uninstall # remove everything gopher-ai installed
```

The installer writes to `${XDG_CONFIG_HOME:-~/.config}/opencode`
(`--config-dir` overrides it). It is safe to run while OpenCode is running:
the background service picks up file changes, and the installer also runs
`opencode reload` when the service is up (`--no-reload` skips that).

## Layout and naming

| Installed path | How you use it |
| --- | --- |
| `skills/gopher-ai/<plugin>/<skill>/SKILL.md` | Skills load by ID, for example `@go` or the skill tool with `start-issue`. OpenCode uses the directory name as the ID. |
| `commands/<plugin>/<command>.md` | Commands run as `/<plugin>/<command>`, for example `/go-dev/lint-fix` or `/go-workflow/cancel-loop`. |
| `agents/<plugin>/<agent>.md` | Subagents named `<plugin>/<agent>`, for example `go-workflow/spec-review-prompt`. |
| `gopher-ai/plugins/<plugin>/` | Runtime scripts, libraries, and templates that skills and commands call. Every `${CLAUDE_PLUGIN_ROOT}` reference points here. |
| `gopher-ai/manifest.txt` | The files the installer owns. |

## Ownership

Only files listed in `gopher-ai/manifest.txt` are replaced or removed. If a
file that gopher-ai did not install already exists at a target path, the
installer leaves it alone and reports the skip. If a `gopher-ai/` directory
exists without a `manifest.txt`, the installer refuses to run rather than
replace it. Files that a previous version
installed but the new version no longer ships are removed. `opencode.json` is
never modified.

Skills installed here take precedence over skills with the same ID in
`~/.claude/skills` and `~/.agents/skills`, following OpenCode's source order.

## Conversion

- Commands keep `description` and their body. `allowed-tools`,
  `argument-hint`, `model`, and `effort` are dropped because OpenCode does not
  use Claude tool allowlists and expects `provider/model` model IDs.
  `$ARGUMENTS` and inline `` !`command` `` blocks work as in Claude Code, with
  one exception: OpenCode expands arguments before running inline shell
  blocks, outside the agent's permission flow, so a block that interpolates
  `$ARGUMENTS` or `$1`… becomes an instruction for the agent to run the
  command with its shell tool instead.
- Agents become `mode: subagent`; Claude's `name` and `model` aliases are
  dropped so OpenCode uses its configured model.
- Codex command-adapter skills are skipped because OpenCode loads the
  commands they wrap directly.

## Not supported

- Hooks. The go-workflow SessionStart, PreToolUse, PostToolUse, and Stop hooks
  use the Claude and Codex hook contracts. OpenCode v2 plugins use a different,
  still-beta `setup` API with no equivalent of a Stop hook that blocks the
  session from ending, so persistent loops (`start-issue`, `ship`, and similar
  workflows) do not re-enter automatically. The workflows still run; they
  stop when the model stops.
- MCP servers. No gopher-ai plugin currently ships one.
