---
argument-hint: "[project-path]"
description: "Initialize Tailwind CSS v4 in an existing project"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(node:*)", "Bash(npm:*)", "Bash(pnpm:*)", "Bash(yarn:*)", "Bash(bun:*)", "Bash(ls:*)", "Bash(fd:*)", "Bash(grep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__install_tailwind", "mcp__tailwindcss__get_tailwind_config_guide"]
---

# Initialize Tailwind CSS v4

**If `$ARGUMENTS` is empty or not provided:**

Initialize Tailwind CSS v4 in the current directory.

**Usage:** `/tailwind-init [project-path]`. `/tailwind-init` (current dir) or `/tailwind-init ./my-app` (specific dir).

**What it does:** detect project type → check for existing Tailwind → choose integration method → install deps → create CSS entry file with v4 syntax → configure the selected build integration.

**v4 key changes:** no `tailwind.config.js` (configure in CSS via `@theme`); single `@import "tailwindcss";`; auto-detects templates (`@source` only for custom paths).

Proceed with initialization in the current directory.

---

**If `$ARGUMENTS` is provided:**

Initialize Tailwind CSS v4 in: `$ARGUMENTS`.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-init" "COMPLETE"; fi`

## Step 1: Validate Environment

```bash
node --version 2>/dev/null || echo "NOT_INSTALLED"
```

If Node.js missing:

> Node.js is required. Install: macOS `brew install node`, nvm, or https://nodejs.org/

Stop and ask the user to install first.

## Step 2: Detect Project Type

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

Read the `packageManager` field in `package.json` and inspect
`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, and `bun.lockb`.
Use the declared manager when it agrees with the lockfile. Otherwise, use the
single lockfile already present. If the signals conflict, ask which manager is
authoritative and stop before changing dependencies. If neither signal exists,
default to npm.

Use the selected manager for every dependency and script command:

| Manager | Add development dependencies | Run a script |
|---------|------------------------------|--------------|
| npm | `npm install -D <PACKAGES>` | `npm run <SCRIPT>` |
| pnpm | `pnpm add -D <PACKAGES>` | `pnpm run <SCRIPT>` |
| Yarn | `yarn add -D <PACKAGES>` | `yarn run <SCRIPT>` |
| Bun | `bun add -d <PACKAGES>` | `bun run <SCRIPT>` |

Do not create a lockfile for a different package manager.

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

## Step 5: Create CSS Entry File

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

Create with v4 syntax:

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

Use only the completion criteria for the selected integration. DO NOT output
`<done>COMPLETE</done>` until every item in that integration's list is TRUE.

### CLI Completion Criteria

1. Dependencies installed
2. CSS entry file created with `@import "tailwindcss"`
3. Build scripts added to `package.json`
4. The selected package manager's `css` script succeeds with zero errors
5. Output CSS is generated at the concrete `<CSS_OUTPUT>` path
6. The stylesheet is referenced through the concrete `<PUBLIC_CSS_URL>`

### Vite Completion Criteria

1. `tailwindcss` and `@tailwindcss/vite` installed
2. CSS entry file created with `@import "tailwindcss"`
3. Tailwind plugin registered in the Vite configuration
4. CSS entry file imported from the application entry point
5. Existing Vite build succeeds and processes the CSS entry without errors

### PostCSS Completion Criteria

1. `tailwindcss`, `@tailwindcss/postcss`, and `postcss` installed
2. CSS entry file created with `@import "tailwindcss"`
3. `@tailwindcss/postcss` registered in the PostCSS configuration
4. CSS entry file connected to the existing PostCSS pipeline
5. Existing PostCSS-backed build succeeds with zero errors

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
