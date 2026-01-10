---
argument-hint: "[project-path]"
description: "Initialize Tailwind CSS v4 in an existing project"
model: claude-sonnet-4-20250514
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__install_tailwind", "mcp__tailwindcss__get_tailwind_config_guide"]
---

# Initialize Tailwind CSS v4

**If `$ARGUMENTS` is empty or not provided:**

Initialize Tailwind CSS v4 in the current directory.

**Usage:** `/tailwind-init [project-path]`

**Examples:**

- `/tailwind-init` - Initialize in current directory
- `/tailwind-init ./my-app` - Initialize in specific directory

**What this command does:**

1. Detects your project type (Go/Templ, React, Vue, Vite, Next.js, plain HTML)
2. Checks for existing Tailwind installation
3. Asks your preferred integration method
4. Installs dependencies
5. Creates CSS entry file with v4 syntax
6. Sets up build scripts

**Tailwind v4 Key Changes:**

- No `tailwind.config.js` needed - configure in CSS with `@theme`
- Single import: `@import "tailwindcss";`
- Auto-detects templates (or use `@source` for custom paths)

Proceed with initialization in the current directory.

---

**If `$ARGUMENTS` is provided:**

Initialize Tailwind CSS v4 in the specified path: `$ARGUMENTS`

## Loop Initialization

Initialize persistent loop to ensure Tailwind setup completes fully:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-init" "COMPLETE"`

## Step 1: Validate Environment

Check that Node.js is installed:

```bash
node --version 2>/dev/null || echo "NOT_INSTALLED"
```

**If Node.js is not installed**, display:

```text
Node.js is required for Tailwind CSS.

Install options:
- macOS: brew install node
- nvm: curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && nvm install --lts
- Direct: https://nodejs.org/
```

Then stop and ask user to install Node.js first.

## Step 2: Detect Project Type

Scan the target directory:

```bash
# Check for package.json
ls package.json 2>/dev/null

# Check for framework indicators
ls vite.config.* next.config.* nuxt.config.* astro.config.* 2>/dev/null

# Check for Go/Templ
ls go.mod 2>/dev/null
fd -e templ -d 3 2>/dev/null | head -3

# Check for existing Tailwind
grep -l "tailwind" package.json 2>/dev/null
ls tailwind.config.* 2>/dev/null
```

**Project type detection:**

| Indicator | Project Type |
|-----------|--------------|
| `vite.config.*` | Vite project |
| `next.config.*` | Next.js |
| `nuxt.config.*` | Nuxt |
| `astro.config.*` | Astro |
| `go.mod` + `*.templ` | Go + Templ |
| `package.json` only | Generic Node project |
| None | Plain HTML/CSS |

**If existing Tailwind found:**

```text
Existing Tailwind installation detected.

Options:
1. Upgrade to v4 - Use /tailwind-migrate instead
2. Reinstall - Remove existing and start fresh
3. Cancel - Keep existing installation
```

## Step 3: Choose Integration Method

Use AskUserQuestion to ask:

| Method | Best For | Package |
|--------|----------|---------|
| **CLI** (recommended) | Most projects, Go/Templ, plain HTML | `@tailwindcss/cli` |
| **Vite Plugin** | Vite-based projects (React, Vue, Svelte) | `@tailwindcss/vite` |
| **PostCSS** | Existing PostCSS pipelines, legacy builds | `@tailwindcss/postcss` |

**Plain explanations:**

- **CLI**: Standalone tool that processes your CSS. Works everywhere, no build system required. Just run `npx @tailwindcss/cli` commands. Best for Go/Templ projects.

- **Vite Plugin**: Tight integration with Vite's hot reload. CSS updates instantly without page refresh. Best for modern frontend frameworks.

- **PostCSS**: Plugs into existing CSS build pipelines. Choose this if you already use PostCSS for other transformations.

## Step 4: Install Dependencies

Based on integration choice, run:

**CLI method:**

```bash
npm install -D tailwindcss @tailwindcss/cli
```

**Vite method:**

```bash
npm install -D tailwindcss @tailwindcss/vite
```

**PostCSS method:**

```bash
npm install -D tailwindcss @tailwindcss/postcss postcss
```

## Step 5: Create CSS Entry File

Determine the CSS file location based on project type:

| Project Type | CSS Path |
|--------------|----------|
| Go/Templ | `static/css/input.css` |
| Vite/React | `src/index.css` or `src/styles/main.css` |
| Next.js | `app/globals.css` or `styles/globals.css` |
| Plain HTML | `css/input.css` |

Create the CSS entry file with v4 syntax:

```css
@import "tailwindcss";

/* Source detection - adjust paths for your templates */
@source "../templates/**/*.templ";
@source "../components/**/*.html";
@source "./**/*.{js,jsx,ts,tsx,vue,svelte}";

/* Theme customization - add your design tokens */
@theme {
  /* Colors using oklch for better color manipulation */
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
  --color-secondary: oklch(0.5 0.02 250);
  --color-secondary-foreground: oklch(1 0 0);

  /* Background and foreground */
  --color-background: oklch(1 0 0);
  --color-foreground: oklch(0.145 0 0);
  --color-muted: oklch(0.95 0 0);
  --color-muted-foreground: oklch(0.4 0 0);
  --color-border: oklch(0.9 0 0);

  /* Custom spacing (extends default scale) */
  --spacing-18: 4.5rem;
  --spacing-22: 5.5rem;
}

/* Dark mode variant */
@variant dark {
  --color-background: oklch(0.145 0 0);
  --color-foreground: oklch(0.985 0 0);
  --color-muted: oklch(0.25 0 0);
  --color-muted-foreground: oklch(0.6 0 0);
  --color-border: oklch(0.3 0 0);
}

/* Base layer customizations */
@layer base {
  html {
    font-family: ui-sans-serif, system-ui, sans-serif;
  }
}
```

**Adjust `@source` paths** based on where templates are located in the project.

## Step 6: Configure Build Scripts

Update `package.json` with build scripts:

**CLI method:**

```json
{
  "scripts": {
    "css": "npx @tailwindcss/cli -i ./css/input.css -o ./css/output.css --minify",
    "css:watch": "npx @tailwindcss/cli -i ./css/input.css -o ./css/output.css --watch"
  }
}
```

**Vite method:**

Update `vite.config.js`:

```javascript
import tailwindcss from '@tailwindcss/vite'

export default {
  plugins: [
    tailwindcss(),
  ],
}
```

**PostCSS method:**

Create or update `postcss.config.mjs`:

```javascript
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

## Step 7: Update .gitignore

Add output CSS to `.gitignore` if using CLI:

```text
# Tailwind output (regenerated on build)
css/output.css
static/css/output.css
```

## Step 8: Final Report

```text
Tailwind CSS v4 Initialized

Files created/modified:
- [CSS entry file path]
- package.json (dependencies + scripts)
- [Config file if Vite/PostCSS]

Next steps:

1. Start development:
   npm run css:watch

2. Include output CSS in your HTML:
   <link href="/css/output.css" rel="stylesheet">

3. Use Tailwind classes:
   <div class="flex items-center gap-4 p-4 bg-primary text-primary-foreground">
     Hello Tailwind v4!
   </div>

4. Customize theme in your CSS file using @theme { ... }

Documentation: https://tailwindcss.com/docs
```

## Notes

- Tailwind v4 auto-detects most template files
- Use `@source` directive only if classes aren't being detected
- The `@theme` directive replaces `tailwind.config.js`
- oklch color format provides better color manipulation than hex/rgb

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Dependencies are installed (tailwindcss, @tailwindcss/cli or equivalent)
2. CSS entry file is created with `@import "tailwindcss"`
3. Build scripts are added to package.json
4. `npm run css` succeeds without errors
5. Output CSS is generated

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, Tailwind may not be properly configured.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
