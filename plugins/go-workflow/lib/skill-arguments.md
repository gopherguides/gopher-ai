# Skill Argument Binding

Argument-bearing workflow skills use `SKILL_ARGS` as their platform-neutral
invocation text. Bind it before running empty-argument checks, validation, or
flag parsing.

Each calling skill supplies its exact qualified Codex invocation name and a
`claude-skill-arguments` compatibility payload. Resolve the value in this
order:

1. If a parent workflow explicitly supplied this child workflow's
   `SKILL_ARGS`, preserve that caller-provided `SKILL_ARGS`, including an
   explicitly empty value. Do not rebind it from the compatibility payload or
   user request.
2. If the trimmed compatibility payload is not the exact literal
   `$ARGUMENTS`, Claude Code expanded it. Bind the expanded payload to
   `SKILL_ARGS`.
3. Otherwise, locate the exact qualified skill invocation that activated the
   current skill in the current user request. Bind the text attached to that
   invocation after the qualified skill name to `SKILL_ARGS`. Codex preserves
   this text in prompt context; it does not export it as a shell variable.
4. If the invocation has no attached text, bind `SKILL_ARGS` to an empty
   string so the calling skill can apply its missing-intent behavior.

Use only the invocation that activated the current skill. Do not bind text
from examples, quoted documentation, or another skill mention. Preserve the
argument text literally, trim only surrounding whitespace, and never evaluate
it as shell code. Treat `SKILL_ARGS` as a workflow-local value rather than
reading an environment variable.
