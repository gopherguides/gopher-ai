---
argument-hint: "[--check]"
description: "Migrate Tailwind CSS v3 configuration to v4 CSS-based config"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_config_guide"]
---

# Migrate Tailwind CSS v3 to v4

**If `$ARGUMENTS` is empty or not provided:**

Migrate Tailwind CSS v3 configuration to v4's CSS-based configuration.

**Usage:** `/tailwind-migrate [options]`

- `/tailwind-migrate` — migrate v3 to v4
- `/tailwind-migrate --check` — preview changes without modifying files

**What it does:** finds `tailwind.config.js`/`.ts` → converts theme to `@theme` directive → converts `content` paths to `@source` directives → updates CSS files to `@import "tailwindcss"` syntax → updates `package.json` deps → optionally removes the old config file.

**Key v4 changes:**

| v3 | v4 |
|----|-----|
| `tailwind.config.js` | CSS `@theme { }` directive |
| `@tailwind base/components/utilities` | `@import "tailwindcss"` |
| `darkMode: 'class'` | `@variant dark { }` |
| `theme.extend.colors` | `--color-*` CSS variables |

Proceed with migration.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- `--check` — preview changes without modifying files
- `--keep-config` — keep old config file after migration (for reference)
- `--backup` — create backup files before modifying

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-migrate" "COMPLETE"; fi`

## Step 1: Find v3 Configuration

```bash
ls tailwind.config.js tailwind.config.ts tailwind.config.cjs tailwind.config.mjs 2>/dev/null
grep '"tailwindcss"' package.json 2>/dev/null
```

If no config found:

> No `tailwind.config.*` file found. Options: (1) project may already use v4 (CSS-based config); (2) use `/tailwind-init` to set up v4 from scratch; (3) check if config is in a non-standard location.

## Step 2: Parse v3 Configuration

Read the config file. Extract: `content` array (becomes `@source` directives), `theme.extend` (becomes `@theme` CSS variables), `darkMode` (becomes `@variant`), `plugins` (check v4 compatibility).

**Plugin compatibility:**

| v3 Plugin | v4 Status |
|-----------|-----------|
| `@tailwindcss/forms` | Built-in (not needed) |
| `@tailwindcss/typography` | `@plugin "@tailwindcss/typography"` |
| `@tailwindcss/container-queries` | Built-in (not needed) |
| `@tailwindcss/aspect-ratio` | Built-in (not needed) |

## Step 3: Generate v4 CSS Configuration

Convert the parsed configuration to v4 CSS:

```css
@import "tailwindcss";

/* From content array */
@source "./src/**/*.{js,jsx,ts,tsx}";
@source "./public/index.html";

/* From theme.extend */
@theme {
  --color-primary: oklch(0.59 0.2 250);   /* #3b82f6 */
  --color-secondary: oklch(0.55 0.02 250); /* #64748b */

  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --spacing-18: 4.5rem;
  --radius-4xl: 2rem;
}

/* From darkMode: 'class' */
@variant dark { /* override theme colors here if needed */ }

/* Plugins */
@plugin "@tailwindcss/typography";
```

For hex → oklch conversion, use https://oklch.com/. Common conversions:

| Hex | oklch |
|-----|-------|
| `#3b82f6` (blue-500) | `oklch(0.59 0.2 250)` |
| `#ef4444` (red-500) | `oklch(0.63 0.26 25)` |
| `#22c55e` (green-500) | `oklch(0.72 0.19 145)` |
| `#f59e0b` (amber-500) | `oklch(0.75 0.18 70)` |
| `#ffffff` / `#000000` | `oklch(1 0 0)` / `oklch(0 0 0)` |

## Step 4: Update CSS Files

```bash
grep -rl '@tailwind' --include="*.css" .
```

Replace v3 directives:

| v3 | v4 |
|----|-----|
| `@tailwind base;` / `components;` / `utilities;` (any/all) | `@import "tailwindcss";` |

Existing `@apply` rules in your CSS continue to work unchanged.

## Step 5: Update package.json

**CLI method (recommended for most projects):**

```bash
npm uninstall tailwindcss postcss autoprefixer
npm install -D tailwindcss@latest @tailwindcss/cli@latest
```

Scripts:

```json
{
  "scripts": {
    "css": "npx @tailwindcss/cli -i ./src/input.css -o ./src/output.css --minify",
    "css:watch": "npx @tailwindcss/cli -i ./src/input.css -o ./src/output.css --watch"
  }
}
```

**PostCSS method (if using an existing PostCSS pipeline):**

```bash
npm uninstall tailwindcss autoprefixer
npm install -D tailwindcss@latest @tailwindcss/postcss@latest postcss
```

## Step 6: Handle PostCSS Config

```js
// v4
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

**Note:** autoprefixer is no longer needed — v4 handles prefixing automatically.

## Step 7: Handle Old Config File

`AskUserQuestion`: "Migration complete. What should we do with `tailwind.config.js`?"

| Option | Description |
|--------|-------------|
| **Delete** (recommended) | Config is now in CSS |
| **Keep as backup** | Rename to `tailwind.config.js.bak` |
| **Keep unchanged** | May cause confusion |

## Step 8: Verify

```bash
npm run css 2>&1 | head -20
```

Common errors:

| Error | Solution |
|-------|----------|
| `Unknown directive @tailwind` | Old directive not removed |
| `Cannot find module` | Plugin not v4 compatible |
| `Invalid CSS` | Syntax error in `@theme` block |

## Step 9: Migration Report

```
## Tailwind v3 → v4 Migration Complete

### Changes
- [CSS file] — @import + @theme
- package.json — v4 dependencies
- [postcss.config.js] — updated (if applicable)
- X custom colors → @theme variables
- Y content paths → @source directives
- Z plugins → @plugin directives
- Dark mode → @variant dark
- tailwind.config.js — removed (or kept per user choice)

### Manual Review Needed
- [ ] Verify custom colors look correct
- [ ] Test dark mode toggle
- [ ] Check responsive breakpoints
- [ ] Verify plugins work correctly

### Next Steps
1. `npm run css:watch`
2. Test thoroughly
3. `/tailwind-audit` to check for any issues
4. Commit
```

Resources: https://tailwindcss.com/docs/upgrade-guide; https://oklch.com/

## Notes

- Always backup files before migration or use `--check` first
- oklch colors may look slightly different than hex — verify visually
- Some v3 plugins may not have v4 equivalents yet
- Test thoroughly after migration, especially dark mode and responsive designs

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. v3 config parsed and analyzed
2. CSS file updated with `@import "tailwindcss"` and `@theme`
3. package.json deps updated to v4
4. `npm run css` (or equivalent) succeeds with zero errors
5. No `@tailwind` directives remain in CSS files

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
