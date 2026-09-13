# shadcn-templ v2

Use after the generation decision in `SKILL.md`. Current source is
https://github.com/axadrn/shadcn-templ. Check release status and the installed CLI help;
the documentation currently labels the v2 line as beta.

## Install components into an existing Go/templ app

Read the project's `go.mod`, `components.json`, and Tailwind entry file first. The current
CLI command is:

```bash
go install github.com/axadrn/shadcn-templ/v2/cmd/shadcn-templ@latest
shadcn-templ init
shadcn-templ add button card
templ generate
go mod tidy
```

Use `init` for an unconfigured project, not as an automatic step in every task. Inspect its
help for the project's CSS path; initialization writes configuration, utilities, and theme
styles. Select a reviewed version for repeatable team installations rather than silently
upgrading existing projects. Do not use force flags to replace customized components.

The CLI resolves dependencies and rewrites imports to the project's module. Inspect the
resulting files and use their actual props, component names, JavaScript loading, and asset
requirements. A deliberate module-import workflow is also documented upstream; preserve
it when already in use instead of mixing ownership models.

For gopher-ai scaffolds, keep the chosen Echo/database/HTMX architecture. Initialize the UI
inside that app, use its actual CSS entry path, and reconcile the generated theme/styles and
source scanning. Do not apply the bundled v1 CSS/head templates or v1 Script() table to v2.
Do not run a second scaffold generator over the same project.

## Legacy migration

After the user approves upgrading, inventory component usage, local customizations, utilities,
CSS tokens, scripts, and assets. Agree on the affected scope, then work in the project's
isolated checkout. Migrate a component and its call sites together; changing import strings
alone is not a migration. Preserve unrelated backend and frontend runtime choices.

The new block collection is separate from the original 222 premium blocks. Use the current
catalog for new sections. When adapting a licensed legacy design, reimplement against the
selected v2 APIs and verify behavior; do not claim that a similarly named block is equivalent.

Run templ generation, Go tests/build, the CSS build, and a browser check of affected
interactions. Inspect the actual component docs for script and accessibility requirements.

## Read only the relevant official docs

- Installation: https://shadcn-templ.com/docs/installation
- CLI: https://shadcn-templ.com/docs/cli
- Documentation index: https://shadcn-templ.com/llms.txt
- Blocks: https://shadcn-templ.com/blocks
- Module imports: follow the current Package Imports / Import Workflow links from installation

Full goilerplate v3 generation is a separate application workflow at https://goilerplate.com/docs.
Use the private goilerplate skill if installed and requested; UI component selection alone
never implies Paid access or a full-app migration.
