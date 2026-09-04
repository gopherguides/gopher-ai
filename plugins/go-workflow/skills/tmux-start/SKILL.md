---
name: tmux-start
description: "Start issue work in a new tmux window with its own worktree. Use when the user has tmux running and wants issue startup to continue outside the current session. SKIP when not inside a tmux session ($TMUX unset) or when the user wants to work in the current session; use start-issue directly."
argument-hint: "<issue-number>"
disable-model-invocation: true
---

# Start Issue in tmux Window

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before requesting decisions, read
`<PLUGIN_ROOT>/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving target or
secret-copy intent.

Bind the invocation arguments as `SKILL_ARGS` for `$go-workflow:tmux-start` by
reading `<PLUGIN_ROOT>/lib/skill-arguments.md` with this Claude Code compatibility payload:
<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

## Empty Arguments

If `SKILL_ARGS` is empty or not provided, explain:

This skill creates or reuses a worktree, opens a new tmux window, launches the
active assistant surface, and sends its qualified `start-issue` invocation
automatically.

**Claude Code:** `/go-workflow:tmux-start <issue-number>`.

**Codex:** `$go-workflow:tmux-start <issue-number>`.

**Prerequisites:** running inside a tmux session (`$TMUX` set); `gh`
authenticated; inside a git repo.

This is a **missing-intent gate**. Request: "What issue number should I start in
a tmux window?" If structured input is unavailable, ask in the final response
and stop before creating a worktree or tmux window.

---

## Clear Worktree State

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-state.sh" clear 2>/dev/null || true
```

## Issue Number

Use `SKILL_ARGS` as the issue number. The script validates that it is numeric
and that the issue exists.

## Environment Files

Check whether the source repo has environment files before creating the
worktree:

```bash
SOURCE_DIR="$(pwd)"
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-create.sh" env-files --source-dir "$SOURCE_DIR"
```

If the output starts with `ENV_FILES_FOUND=true`, follow the shared
**missing-intent gate**. Request explicit consent: "Found environment files
that may contain secrets. Copy them to the new worktree?" Stop before worktree
or tmux creation when structured input is unavailable.

## Start tmux Workflow

Bind `SURFACE` from the active assistant before invoking the script. Claude
Code binds `claude`; Codex binds `codex`. Do not infer the surface from
installed executables or environment variables.

```bash
SURFACE="<claude-or-codex>"
```

If copying environment files was explicitly authorized:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/tmux-start.sh" "$SKILL_ARGS" --surface "$SURFACE" --copy-env
```

Otherwise:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/tmux-start.sh" "$SKILL_ARGS" --surface "$SURFACE" --no-copy-env
```

The script validates prerequisites, creates or reuses the standard issue
worktree, registers worktree state, opens or switches to the issue tmux window,
launches the bound assistant, waits for a Claude or Codex prompt or stable
launch marker, and sends `/go-workflow:start-issue <issue-number>` for Claude
or `$go-workflow:start-issue <issue-number>` for Codex. Direct script callers
that omit `--surface` retain the Claude default.

Set `GOPHER_AI_TMUX_ASSISTANT_CMD` or pass `--assistant-cmd` to override the
launch command for either surface. The neutral override takes precedence over
`GOPHER_AI_TMUX_CLAUDE_CMD` and `--claude-cmd`, which remain supported for
Claude compatibility. Defaults are `claude --dangerously-skip-permissions`
and `codex --dangerously-bypass-approvals-and-sandbox`.
