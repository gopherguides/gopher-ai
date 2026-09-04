---
name: cancel-loop
description: "Cancel active persistent go-workflow loop state. Use when the user explicitly invokes the qualified cancel-loop skill with an optional loop name."
argument-hint: "[loop-name]"
disable-model-invocation: true
---

# Cancel Loop

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before cancellation, read `<PLUGIN_ROOT>/lib/driver-interaction.md` and follow
its cross-platform capability-binding rules.

Bind the invocation arguments as `SKILL_ARGS` for `$go-workflow:cancel-loop` by
reading `<PLUGIN_ROOT>/lib/skill-arguments.md` with this Claude Code compatibility payload:
<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

## Invocation

- Codex: `$go-workflow:cancel-loop [loop-name]`
- Claude Code: `/go-workflow:cancel-loop [loop-name]`

With no loop name, cancel every active loop owned by the current repository.
With a loop name, cancel only that loop and leave unrelated loop state untouched.

## Execute Cancellation

```bash
if [ ! -x "<PLUGIN_ROOT>/scripts/cleanup-loop.sh" ]; then
  echo "ERROR: Plugin cache stale. Refresh the go-workflow plugin and restart the active assistant."
  exit 1
fi
/bin/bash "<PLUGIN_ROOT>/scripts/cleanup-loop.sh" "$SKILL_ARGS"
```

Report the helper output exactly. Do not claim a loop was removed when the
helper reports that no matching active loop exists.
