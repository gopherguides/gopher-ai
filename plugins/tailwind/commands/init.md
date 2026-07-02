---
argument-hint: "[project-path]"
description: "Initialize Tailwind CSS v4 in an existing project"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(node:*)", "Bash(npm:*)", "Bash(npx:*)", "Bash(ls:*)", "Bash(fd:*)", "Bash(grep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__install_tailwind", "mcp__tailwindcss__get_tailwind_config_guide"]
---

# Initialize Tailwind CSS v4

**If `$ARGUMENTS` is empty or not provided:**

Initialize Tailwind CSS v4 in the current directory.

**Usage:** `/tailwind-init [project-path]`. `/tailwind-init` (current dir) or `/tailwind-init ./my-app` (specific dir).

**What it does:** detect project type → check for existing Tailwind → choose integration method → install deps → create CSS entry file with v4 syntax → set up build scripts.

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

```bash
# CLI (recommended)
npm install -D tailwindcss @tailwindcss/cli

# Vite
npm install -D tailwindcss @tailwindcss/vite

# PostCSS
npm install -D tailwindcss @tailwindcss/postcss postcss
```

## Step 5: Create CSS Entry File

CSS path by project type:

| Project | Path |
|---------|------|
| Go/Templ | `static/css/input.css` |
| Vite/React | `src/index.css` or `src/styles/main.css` |
| Next.js | `app/globals.css` or `styles/globals.css` |
| Plain HTML | `css/input.css` |

Create with v4 syntax:

```css
@import "tailwindcss";

/* Adjust paths for your templates */
@source "../templates/**/*.templ";
@source "../components/**/*.html";
@source "./**/*.{js,jsx,ts,tsx,vue,svelte}";

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

@variant dark {
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

Adjust `@source` paths based on where templates are located.

## Step 6: Configure Build Scripts

**CLI:**

```json
{
  "scripts": {
    "css": "npx @tailwindcss/cli -i ./css/input.css -o ./css/output.css --minify",
    "css:watch": "npx @tailwindcss/cli -i ./css/input.css -o ./css/output.css --watch"
  }
}
```

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

```text
# Tailwind output (regenerated on build)
css/output.css
static/css/output.css
```

## Step 8: Final Report

```
Tailwind CSS v4 Initialized

Files created/modified:
- [CSS entry file path]
- package.json (dependencies + scripts)
- [Config file if Vite/PostCSS]

Next steps:
1. npm run css:watch
2. Include in HTML: <link href="/css/output.css" rel="stylesheet">
3. Use classes: <div class="flex items-center gap-4 p-4 bg-primary text-primary-foreground">…
4. Customize theme via @theme { ... } in the CSS file

Docs: https://tailwindcss.com/docs
```

## Notes

- v4 auto-detects most template files; use `@source` only when classes aren't being detected
- `@theme` replaces `tailwind.config.js`
- oklch provides better color manipulation than hex/rgb

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Dependencies installed
2. CSS entry file created with `@import "tailwindcss"`
3. Build scripts added to `package.json`
4. `npm run css` (or equivalent) succeeds with zero errors
5. Output CSS is generated

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
