---
argument-hint: "[project-path]"
description: "Initialize Tailwind CSS v4 in an existing project"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(node:*)", "Bash(npm:*)", "Bash(pnpm:*)", "Bash(yarn:*)", "Bash(bun:*)", "Bash(ls:*)", "Bash(fd:*)", "Bash(grep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Initialize Tailwind CSS v4

**If `$ARGUMENTS` is empty or not provided:**

Initialize Tailwind CSS v4 in the current directory.

**Usage:** `/tailwind-init [project-path]`. `/tailwind-init` (current dir) or `/tailwind-init ./my-app` (specific dir).

**What it does:** detect project type → check for existing Tailwind → choose integration method → install deps → create CSS entry file with v4 syntax → configure the selected build integration.

**v4 key changes:** no `tailwind.config.js` (configure in CSS via `@theme`); single `@import "tailwindcss";`; auto-detects templates (`@source` only for custom paths).

Proceed after binding the current directory as the initialization operation
root described below.

---

**If `$ARGUMENTS` is provided:**

Initialize Tailwind CSS v4 in: `$ARGUMENTS`.

## Initialization Operation Root

Parse at most one positional project path from the invocation arguments. Bind
the requested project path to `<INIT_TARGET>` as one concrete normalized
absolute directory. When no path was provided, bind the invocation's current
directory. Stop before any mutation when the path does not exist, is not a
directory, or extra positional arguments remain. Bind `<INIT_TARGET>` once and
do not re-derive or broaden it later.

Treat `<INIT_TARGET>` as the application and integration mutation scope for the
entire workflow. Execute application discovery, file edits, integration
configuration, and direct tool validation with `<INIT_TARGET>` as the working
directory. Resolve every application path, including the member
`package.json`, CSS entries, build configuration, and `.gitignore`, against
`<INIT_TARGET>`. The only permitted ancestor discovery and mutation are the
read-only package-ownership search and owning lockfile update described under
Package Manager Selection. Do not treat the package root as a broader
application mutation scope, and do not inspect or change the invocation
directory unless it is `<INIT_TARGET>` or the owning package root.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-init" "COMPLETE"; fi`

## Step 1: Validate Environment

Run this environment check with `<INIT_TARGET>` as its working directory:

```bash
node --version 2>/dev/null || echo "NOT_INSTALLED"
```

If Node.js missing:

> Node.js is required. Install: macOS `brew install node`, nvm, or https://nodejs.org/

Stop and ask the user to install first.

## Step 2: Detect Project Type

Run all discovery commands with `<INIT_TARGET>` as their working directory:

```bash
ls package.json 2>/dev/null
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
ls vite.config.* next.config.* nuxt.config.* astro.config.* 2>/dev/null
ls go.mod 2>/dev/null
fd -e templ -d 3 2>/dev/null | head -3
grep -l "tailwind" package.json 2>/dev/null
ls tailwind.config.* 2>/dev/null
```

| Indicator | Project Type |
|-----------|--------------|
| `vite.config.*` | Vite |
| `next.config.*` | Next.js |
| `nuxt.config.*` | Nuxt |
| `astro.config.*` | Astro |
| `go.mod` + `*.templ` | Go + Templ |
| `package.json` only | Generic Node |
| None | Plain HTML/CSS |

## Package Manager Selection

Starting at `<INIT_TARGET>`, walk only its ancestor directories and inspect
package-manager ownership evidence without writing. Find the nearest ancestor
that owns the target through a package-manager declaration, lockfile, or
workspace configuration such as `package.json` `workspaces` or
`pnpm-workspace.yaml`. Confirm that the workspace configuration actually
includes `<INIT_TARGET>`, then bind that ancestor to `<PACKAGE_ROOT>` and bind
the requested member's concrete package name or root-relative path to
`<WORKSPACE_MEMBER>`. For a standalone project, `<PACKAGE_ROOT>` and
`<INIT_TARGET>` are the same directory.

At the owning root, read the `packageManager` field and inspect
`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, and `bun.lockb`.
Use the declared manager when it agrees with the owning lockfile. Otherwise,
use the single owning lockfile already present. Treat competing ownership
roots, a member declaration that disagrees with its owning root, multiple
manager lockfiles, or a workspace that does not clearly include the requested
target as conflicting signals. Ask which root and manager are authoritative
and stop before changing dependencies. If no ownership evidence exists at the
target or any ancestor, bind `<PACKAGE_ROOT>` to `<INIT_TARGET>` and default to
npm.

Use the selected manager for every dependency and script command:

| Manager | Add development dependencies | Run a script |
|---------|------------------------------|--------------|
| npm | `npm install -D <PACKAGES>` | `npm run <SCRIPT>` |
| pnpm | `pnpm add -D <PACKAGES>` | `pnpm run <SCRIPT>` |
| Yarn | `yarn add -D <PACKAGES>` | `yarn run <SCRIPT>` |
| Bun | `bun add -d <PACKAGES>` | `bun run <SCRIPT>` |

Do not create a lockfile for a different package manager.
When `<PACKAGE_ROOT>` equals `<INIT_TARGET>`, run the selected package manager
there normally. For a workspace member, run it from `<PACKAGE_ROOT>` with that
manager's explicit workspace/member selector bound to `<WORKSPACE_MEMBER>`.
Never run an unscoped install or script command at the workspace root for a
member request. Verify that dependency changes affect only the requested
member manifest and the owning lockfile; do not modify unrelated packages.
Never create a lockfile in the member or at a different ancestor when the
owning workspace already has one.

If existing Tailwind detected, ask via `AskUserQuestion`:

| Option | Action |
|--------|--------|
| **Upgrade to v4** | Recommend `/tailwind-migrate` instead |
| **Reinstall** | Remove existing and start fresh |
| **Cancel** | Keep existing installation |

## Step 3: Choose Integration Method

`AskUserQuestion`:

| Method | Best For | Package |
|--------|----------|---------|
| **CLI** (recommended) | Most projects, Go/Templ, plain HTML | `@tailwindcss/cli` |
| **Vite Plugin** | Vite-based projects (React, Vue, Svelte) | `@tailwindcss/vite` |
| **PostCSS** | Existing PostCSS pipelines | `@tailwindcss/postcss` |

- **CLI:** standalone tool that processes CSS — works everywhere, no build system required.
- **Vite Plugin:** tight integration with Vite hot reload; instant CSS updates.
- **PostCSS:** plugs into existing PostCSS pipelines.

## Step 4: Install Dependencies

Use the selected package manager's add-development-dependencies command with
the package set for the selected integration:

| Integration | Packages |
|-------------|----------|
| CLI | `tailwindcss @tailwindcss/cli` |
| Vite | `tailwindcss @tailwindcss/vite` |
| PostCSS | `tailwindcss @tailwindcss/postcss postcss` |

## Step 5: Create or Merge CSS Entry File

CSS path by project type:

| Project | Path |
|---------|------|
| Go/Templ | `static/css/input.css` |
| Vite/React | `src/index.css` or `src/styles/main.css` |
| Next.js | `app/globals.css` or `styles/globals.css` |
| Plain HTML | `css/input.css` |

Bind the selected CSS entry path to `<CSS_ENTRY>`. For the CLI integration,
derive a distinct sibling output path and bind it to `<CSS_OUTPUT>`: replace an
`input.css` filename with `output.css`, or append `.generated.css` to another
stem. Never use the entry file itself as the output. Resolve how the project
serves that output and bind its browser-facing URL to `<PUBLIC_CSS_URL>`.

If `<CSS_ENTRY>` does not exist, create it with the full v4 template below.
Use this full template only for a new file.

If `<CSS_ENTRY>` already exists, read the entire file before editing and
perform a verified in-place merge. Never overwrite an existing CSS entry, even
when the user selected Reinstall. Build only the minimal missing Tailwind
import and configuration fragments instead of inserting the full template.

For an existing entry:

1. Preserve every existing import, rule, comment, at-rule, declaration, and
   their relative order. Insert a missing Tailwind import after any `@charset`
   and existing imports but before the first ordinary rule or non-import
   at-rule, without moving existing content.
2. Reuse an equivalent existing Tailwind import instead of adding a duplicate.
   Merge only missing `@source`, `@theme`, `@custom-variant`, dark-selector, and
   `@layer` configuration. Deduplicate exact directives and declarations.
3. Treat incompatible Tailwind import modifiers, a theme variable with a
   different existing value, a conflicting custom variant, or another
   semantic mismatch as conflicting Tailwind configuration. Ask which value or
   behavior is authoritative and stop before writing the dependent change.
4. Compare the original and proposed content with only the proposed insertions
   excluded. Do not write unless all original content remains identical and in
   the same order.

For an absent entry, create this template with v4 syntax:

```css
@import "tailwindcss";

/* Replace with paths relative to <CSS_ENTRY> */
@source "<RELATIVE_TEMPLATE_PATH>/**/*.templ";
@source "<RELATIVE_COMPONENT_PATH>/**/*.html";
@source "<RELATIVE_SOURCE_PATH>/**/*.{js,jsx,ts,tsx,vue,svelte}";

/* Design tokens — add yours */
@theme {
  /* Colors in oklch for better manipulation */
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
  --color-secondary: oklch(0.5 0.02 250);
  --color-secondary-foreground: oklch(1 0 0);

  /* Background / foreground */
  --color-background: oklch(1 0 0);
  --color-foreground: oklch(0.145 0 0);
  --color-muted: oklch(0.95 0 0);
  --color-muted-foreground: oklch(0.4 0 0);
  --color-border: oklch(0.9 0 0);

  /* Custom spacing */
  --spacing-18: 4.5rem;
  --spacing-22: 5.5rem;
}

@custom-variant dark (&:where(.dark, .dark *));

.dark {
  --color-background: oklch(0.145 0 0);
  --color-foreground: oklch(0.985 0 0);
  --color-muted: oklch(0.25 0 0);
  --color-muted-foreground: oklch(0.6 0 0);
  --color-border: oklch(0.3 0 0);
}

@layer base {
  html { font-family: ui-sans-serif, system-ui, sans-serif; }
}
```

Replace every placeholder with a concrete path relative to the directory
containing `<CSS_ENTRY>`, and verify each path resolves to the intended files.
Bind `<CSS_ENTRY>`, `<CSS_OUTPUT>`, and every integration configuration path
inside `<INIT_TARGET>`; do not create or modify a path outside the operation
root.

## Step 6: Configure Selected Integration

**CLI:**

```json
{
  "scripts": {
    "css": "tailwindcss -i <CSS_ENTRY> -o <CSS_OUTPUT> --minify",
    "css:watch": "tailwindcss -i <CSS_ENTRY> -o <CSS_OUTPUT> --watch"
  }
}
```

Replace `<CSS_ENTRY>` and `<CSS_OUTPUT>` with their concrete project-relative
paths before writing the scripts.

**Vite** — `vite.config.js`:

```javascript
import tailwindcss from '@tailwindcss/vite'
export default {
  plugins: [tailwindcss()],
}
```

**PostCSS** — `postcss.config.mjs`:

```javascript
export default {
  plugins: { '@tailwindcss/postcss': {} },
}
```

## Step 7: Update .gitignore (CLI only)

Add the concrete `<CSS_OUTPUT>` path to `.gitignore` as regenerated build
output. Do not add example paths that the selected CLI script does not write.

## Step 8: Verify Selected Integration

Run only the verification path for the selected integration.
Run direct tool verification with `<INIT_TARGET>` as its working directory. If
verification invokes a package-manager script for a workspace member, run it
from `<PACKAGE_ROOT>` with the explicit `<WORKSPACE_MEMBER>` selector. Validate
only application files and artifacts associated with `<INIT_TARGET>`.

### CLI Verification

Run the configured build and confirm the output file exists and is non-empty:

Run the `css` script with the selected package manager, for example
`npm run css`, `pnpm run css`, `yarn run css`, or `bun run css`.

### Vite Verification

Ensure the CSS entry file is imported from the application entry point, then
run the project's existing Vite build with the selected package manager.

Confirm the build succeeds and processes the Tailwind CSS entry without
errors. Do not add CLI-only `css` scripts or a standalone output path.

### PostCSS Verification

Ensure the CSS entry file is connected to the project's existing PostCSS
pipeline, then run that pipeline's existing build command. Confirm the build
succeeds with `@tailwindcss/postcss` enabled. Do not add CLI-only `css` scripts
or require a standalone output path.

If the selected Vite or PostCSS project has no build command, report the
missing project-level command and ask which existing command should verify the
integration rather than silently adding a CLI workflow.

## Step 9: Final Report

Use only the next steps for the selected integration.

```
Tailwind CSS v4 Initialized

Initialization target: <INIT_TARGET>

Files created/modified:
- [CSS entry file path]
- package.json (dependencies, plus scripts for CLI)
- [Config file if Vite/PostCSS]

Verification:
- [Selected integration and successful verification command]
- Package manager: [npm, pnpm, Yarn, or Bun]

Docs: https://tailwindcss.com/docs
```

### CLI Next Steps

```text
Next steps:
1. Run the `css:watch` script with the selected package manager
2. Include in HTML: <link href="<PUBLIC_CSS_URL>" rel="stylesheet">
3. Use classes: <div class="flex items-center gap-4 p-4 bg-primary text-primary-foreground">…
4. Customize theme via @theme { ... } in the CSS file
```

### Vite Next Steps

```text
Next steps:
1. Import the CSS entry file from the application entry point
2. Run the existing Vite development command with the selected package manager
3. Use classes: <div class="flex items-center gap-4 p-4 bg-primary text-primary-foreground">…
4. Customize theme via @theme { ... } in the CSS file
```

### PostCSS Next Steps

```text
Next steps:
1. Run the existing PostCSS-backed development or watch command
2. Include the pipeline's resulting stylesheet through the project's existing asset flow
3. Use classes: <div class="flex items-center gap-4 p-4 bg-primary text-primary-foreground">…
4. Customize theme via @theme { ... } in the CSS file
```

## Notes

- v4 auto-detects most template files; use `@source` only when classes aren't being detected
- `@theme` replaces `tailwind.config.js`
- oklch provides better color manipulation than hex/rgb

## Completion Criteria

Use only the completion criteria for the selected integration, together with
the Target Scope criteria. DO NOT output `<done>COMPLETE</done>` until every
applicable item is TRUE.

### CSS Entry Preservation Criteria

1. A new `<CSS_ENTRY>` received the full template only when the file was absent
2. An existing `<CSS_ENTRY>` was read completely and changed only by a verified in-place merge
3. Every pre-existing import, rule, comment, at-rule, declaration, and relative order was preserved
4. The Tailwind import remains in CSS's legal import region and no equivalent directive was duplicated
5. Conflicting Tailwind configuration was resolved explicitly before any dependent write

### Target Scope Completion Criteria

1. `<INIT_TARGET>` is one concrete normalized absolute directory
2. Every application discovery, integration edit, and direct tool command used `<INIT_TARGET>` as its working directory
3. `<PACKAGE_ROOT>` is the nearest verified package or workspace owner of `<INIT_TARGET>`
4. Every workspace package-manager command explicitly targeted `<WORKSPACE_MEMBER>` and changed no unrelated package
5. Every application read, write, integration edit, and validation stayed within `<INIT_TARGET>`; only the verified owning lockfile could change at `<PACKAGE_ROOT>`
6. No file in the invocation directory changed unless it is `<INIT_TARGET>` or the verified owning package root

### CLI Completion Criteria

1. Dependencies installed
2. CSS entry file created or losslessly merged with `@import "tailwindcss"`
3. Build scripts added to `package.json`
4. The selected package manager's `css` script succeeds with zero errors
5. Output CSS is generated at the concrete `<CSS_OUTPUT>` path
6. The stylesheet is referenced through the concrete `<PUBLIC_CSS_URL>`

### Vite Completion Criteria

1. `tailwindcss` and `@tailwindcss/vite` installed
2. CSS entry file created or losslessly merged with `@import "tailwindcss"`
3. Tailwind plugin registered in the Vite configuration
4. CSS entry file imported from the application entry point
5. Existing Vite build succeeds and processes the CSS entry without errors

### PostCSS Completion Criteria

1. `tailwindcss`, `@tailwindcss/postcss`, and `postcss` installed
2. CSS entry file created or losslessly merged with `@import "tailwindcss"`
3. `@tailwindcss/postcss` registered in the PostCSS configuration
4. CSS entry file connected to the existing PostCSS pipeline
5. Existing PostCSS-backed build succeeds with zero errors

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
