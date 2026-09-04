# Codex Command Adapter

This adapter lets a Codex skill reuse the matching Claude Code command body as
one cross-platform workflow. Apply these rules before following that body.

## Invocation Arguments

Bind the invocation text to `SKILL_ARGS` without evaluating it:

1. Preserve `SKILL_ARGS` when a parent workflow explicitly supplied it,
   including an explicitly empty value.
2. On Claude Code, bind the injected `$ARGUMENTS` value.
3. On Codex with an explicit invocation, find the exact qualified
   `$tailwind:<skill-name>` token and bind only the text following that name.
4. When Codex selected audit or optimize implicitly, derive the target and
   relevant options from the activating request.
5. Bind `SKILL_ARGS` to an empty string only when neither an explicit argument
   nor an implicit target or option is present.

Treat every `$ARGUMENTS` or `${ARGUMENTS}` reference in the command body as a
reference to `SKILL_ARGS`. Preserve whitespace and never read arguments from a
shell environment variable.

The selected command body must parse and consume every bound target. Init binds
its explicit project path to `<INIT_TARGET>`. Audit binds it to
`<AUDIT_TARGET>` and optimize binds it to `<OPTIMIZE_TARGET>`.
Target-scoped discovery, analysis, reporting, and fixes must use the matching
binding consistently. When an explicit or implicit target exists, never fall
back to the current directory. Never broaden a target-scoped operation to the
repository root.

## Plugin Resources

Resolve the concrete absolute plugin root once from the selected skill. Treat
every `$CLAUDE_PLUGIN_ROOT` or `${CLAUDE_PLUGIN_ROOT}` reference in the command
body as that concrete root. Replace notation before running a command or
reading a resource.

## Persistent Loop State

On Codex, skip every `Loop Initialization` section, do not run
`setup-loop.sh`, do not create persistent loop state, and do not emit a
`<done>...</done>` marker. Perform any required iteration within the current
invocation and preserve the command body completion criteria.

On Claude Code, follow the loop initialization and completion-marker protocol
unchanged.

## Read-only Defaults

On Codex, audit and optimize are read-only unless `--fix` is present. Do not modify project files, install dependencies, or overwrite generated CSS during
a read-only run. Put disposable measurement output under the active temporary
directory and use only the project toolchain that is already installed. If a
measurement needs a missing dependency, report that limitation and continue
with the checks that remain available.

Treat `--report` as a request to render a detailed report in the response
unless the user supplied an output path. Migration with `--check` is also
read-only. When `--fix` is present, limit changes to the requested workflow,
preserve unrelated work, and verify every modified output.

## Documentation Sources

Use repository evidence and the bundled Tailwind references first. Consult the
official documentation through the host assistant when current upstream
behavior matters. If network access is unavailable, continue with the bundled
references and state the verification limitation rather than blocking the
workflow.

## Native Capabilities

Map command-body capabilities by intent:

- Resolve technical choices from the project type and existing configuration.
- For a required product choice that repository evidence cannot resolve, use
  the active surface structured-input capability when available. Otherwise ask
  one concise question and stop before the dependent mutation.
- Map file and shell operations to the active surface equivalents while
  preserving the command body safety intent.
- Render reports in the response unless the user explicitly requested a file.

When the command body names a Claude slash command, use the corresponding
qualified Codex skill in Codex: `$tailwind:init`, `$tailwind:migrate`,
`$tailwind:audit`, or `$tailwind:optimize`.
