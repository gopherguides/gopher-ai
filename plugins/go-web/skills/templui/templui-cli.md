# templUI v1 dependencies and CLI

Apply this reference only after the generation check and upgrade question in `SKILL.md`.
For shadcn-templ v2 use `shadcn-templ.md` instead.

## Match the existing ownership model

- **Module imports** (`github.com/templui/templui/components/...`), including legacy premium
  blocks: preserve the project's compatible v1 pin in `go.mod`. For an imported block,
  consult the block library's `go.mod`. Do not run `templui add` and expect module imports
  to resolve to newly copied local files. Include module component sources in Tailwind's scan.
- **Local copies** (`<project-module>/components/...`): use the v1 CLI, inspect `.templui.json`,
  and keep imports pointed at the configured local directory. Check dependencies and scripts
  when adapting a module-import block to local copies.

## CLI copy workflow

Install from the v1 branch, then choose a reviewed v1 tag or commit for reproducible team
installs. The executable is under `cmd/templui`, not the module root:

```bash
go install github.com/templui/templui/cmd/templui@v1
templui --version
templui init@v1
templui add@v1 button card
templui list@v1
```

Use `init` only when configuration is absent or initialization is explicitly requested.
The `@v1` suffix keeps component retrieval on the legacy branch. Preserve an existing pin
instead of upgrading it incidentally. Inspect `templui --help` before using flags: current
v1 uses `--force` before the subcommand, not `add -f`. Only overwrite reviewed local component
changes with authorization. There is no `templui new` command in the current v1 CLI.

Verify interactive components' `Script()` functions and dependency scripts against their
installed source. Run templ generation, `go mod tidy`, and the project's Go/CSS checks after
an authorized dependency change.
