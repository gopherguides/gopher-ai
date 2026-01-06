---
argument-hint: "[--check]"
description: "Migrate Tailwind CSS v3 configuration to v4 CSS-based config"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_config_guide"]
---

# Migrate Tailwind CSS v3 to v4

**If `$ARGUMENTS` is empty or not provided:**

Migrate Tailwind CSS v3 configuration to v4's CSS-based configuration.

**Usage:** `/tailwind-migrate [options]`

**Examples:**

- `/tailwind-migrate` - Migrate v3 to v4
- `/tailwind-migrate --check` - Check what would change without modifying files

**What this command does:**

1. Finds and parses your `tailwind.config.js` or `tailwind.config.ts`
2. Converts theme configuration to CSS `@theme` directive
3. Converts `content` paths to `@source` directives
4. Updates CSS files to use `@import "tailwindcss"` syntax
5. Updates package.json dependencies to v4
6. Optionally removes the old config file

**Key v4 Changes:**

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

- **--check**: Preview changes without modifying files
- **--keep-config**: Keep old config file after migration (for reference)
- **--backup**: Create backup files before modifying

## Step 1: Find v3 Configuration

Look for Tailwind v3 configuration files:

```bash
# Check for config files
ls tailwind.config.js tailwind.config.ts tailwind.config.cjs tailwind.config.mjs 2>/dev/null

# Check package.json for Tailwind version
grep '"tailwindcss"' package.json 2>/dev/null
```

**If no config found:**

```text
No tailwind.config.* file found.

Options:
1. This project may already be using Tailwind v4 (CSS-based config)
2. Use /tailwind-init to set up Tailwind v4 from scratch
3. Check if config is in a non-standard location
```

## Step 2: Parse v3 Configuration

Read and parse the configuration file. Extract:

### Theme Configuration

```javascript
// v3 tailwind.config.js
module.exports = {
  content: ['./src/**/*.{js,jsx,ts,tsx}', './public/index.html'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: '#3b82f6',
        secondary: '#64748b',
        accent: {
          light: '#fef3c7',
          DEFAULT: '#f59e0b',
          dark: '#b45309',
        },
      },
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        display: ['Lexend', 'sans-serif'],
      },
      spacing: {
        '18': '4.5rem',
        '22': '5.5rem',
      },
      borderRadius: {
        '4xl': '2rem',
      },
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
  ],
}
```

### Content/Source Paths

Extract the `content` array - these become `@source` directives.

### Plugins

Note any plugins - check v4 compatibility:

| v3 Plugin | v4 Status |
|-----------|-----------|
| `@tailwindcss/forms` | Built-in (not needed) |
| `@tailwindcss/typography` | `@plugin "@tailwindcss/typography"` |
| `@tailwindcss/container-queries` | Built-in (not needed) |
| `@tailwindcss/aspect-ratio` | Built-in (not needed) |

## Step 3: Generate v4 CSS Configuration

Convert the parsed configuration to v4 CSS syntax:

```css
@import "tailwindcss";

/* Source paths (from content array) */
@source "./src/**/*.{js,jsx,ts,tsx}";
@source "./public/index.html";

/* Theme configuration (from theme.extend) */
@theme {
  /* Colors - convert hex to oklch for better manipulation */
  --color-primary: oklch(0.59 0.2 250); /* #3b82f6 */
  --color-secondary: oklch(0.55 0.02 250); /* #64748b */
  --color-accent-light: oklch(0.96 0.05 85); /* #fef3c7 */
  --color-accent: oklch(0.75 0.18 70); /* #f59e0b */
  --color-accent-dark: oklch(0.52 0.15 50); /* #b45309 */

  /* Font families */
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --font-display: "Lexend", ui-sans-serif, system-ui, sans-serif;

  /* Custom spacing */
  --spacing-18: 4.5rem;
  --spacing-22: 5.5rem;

  /* Custom border radius */
  --radius-4xl: 2rem;
}

/* Dark mode (from darkMode: 'class') */
@variant dark {
  /* Override theme colors for dark mode if needed */
}

/* Plugins */
@plugin "@tailwindcss/typography";

/* Base layer customizations */
@layer base {
  html {
    font-family: var(--font-sans);
  }
}
```

### Color Conversion Table

Convert common hex colors to oklch:

| Hex | oklch | Notes |
|-----|-------|-------|
| `#3b82f6` (blue-500) | `oklch(0.59 0.2 250)` | Primary blue |
| `#ef4444` (red-500) | `oklch(0.63 0.26 25)` | Error red |
| `#22c55e` (green-500) | `oklch(0.72 0.19 145)` | Success green |
| `#f59e0b` (amber-500) | `oklch(0.75 0.18 70)` | Warning amber |
| `#6366f1` (indigo-500) | `oklch(0.58 0.22 275)` | Accent indigo |
| `#ffffff` | `oklch(1 0 0)` | White |
| `#000000` | `oklch(0 0 0)` | Black |

Use the oklch color picker: https://oklch.com/

## Step 4: Update CSS Files

Find CSS files with old directives:

```bash
grep -rl '@tailwind' --include="*.css" .
```

Replace v3 directives:

| v3 | v4 |
|----|-----|
| `@tailwind base;` | Remove (included in import) |
| `@tailwind components;` | Remove (included in import) |
| `@tailwind utilities;` | Remove (included in import) |
| All three | `@import "tailwindcss";` |

**Before:**
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

.custom-class {
  @apply p-4;
}
```

**After:**
```css
@import "tailwindcss";

@source "./src/**/*.{js,jsx}";

@theme {
  /* moved from tailwind.config.js */
}

.custom-class {
  @apply p-4;
}
```

## Step 5: Update package.json

Update dependencies based on your integration method:

**For CLI method (recommended for most projects):**

```bash
# Remove old packages
npm uninstall tailwindcss postcss autoprefixer

# Install v4 CLI
npm install -D tailwindcss@latest @tailwindcss/cli@latest
```

Update scripts:

```json
{
  "scripts": {
    "css": "npx @tailwindcss/cli -i ./src/input.css -o ./src/output.css --minify",
    "css:watch": "npx @tailwindcss/cli -i ./src/input.css -o ./src/output.css --watch"
  }
}
```

**For PostCSS method (if using existing PostCSS pipeline):**

```bash
# Remove old packages but keep postcss
npm uninstall tailwindcss autoprefixer

# Install v4 with PostCSS plugin
npm install -D tailwindcss@latest @tailwindcss/postcss@latest postcss
```

## Step 6: Handle PostCSS (if applicable)

If project uses PostCSS, update `postcss.config.js`:

**v3:**
```javascript
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
```

**v4:**
```javascript
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

Note: autoprefixer is no longer needed - v4 handles prefixing automatically.

## Step 7: Handle Old Config File

After successful migration, ask user:

```text
Migration complete. What should we do with tailwind.config.js?

1. Delete it (recommended) - Config is now in CSS
2. Keep it (reference) - Rename to tailwind.config.js.bak
3. Keep it (unchanged) - May cause confusion
```

## Step 8: Verify Migration

Run a test build:

```bash
npm run css 2>&1 | head -20
```

Check for errors. Common issues:

| Error | Solution |
|-------|----------|
| `Unknown directive @tailwind` | Old directive not removed |
| `Cannot find module` | Plugin not v4 compatible |
| `Invalid CSS` | Syntax error in @theme block |

## Step 9: Migration Report

```text
## Tailwind v3 to v4 Migration Complete

### Changes Made

**Files modified:**
- [CSS file] - Updated directives and added @theme
- package.json - Updated dependencies
- [postcss.config.js] - Updated for v4 (if applicable)

**Configuration migrated:**
- X custom colors → @theme CSS variables
- Y content paths → @source directives
- Z plugins → @plugin directives
- Dark mode → @variant dark

**Files removed:**
- tailwind.config.js (config now in CSS)

### Breaking Changes

[List any potential breaking changes]

### Manual Review Needed

- [ ] Verify custom colors look correct
- [ ] Test dark mode toggle
- [ ] Check responsive breakpoints
- [ ] Verify plugins work correctly

### Next Steps

1. Run `npm run css:watch` to start development
2. Test the application thoroughly
3. Run `/tailwind-audit` to check for any issues
4. Commit changes

### Resources

- Upgrade guide: https://tailwindcss.com/docs/upgrade-guide
- v4 documentation: https://tailwindcss.com/docs
- oklch colors: https://oklch.com/
```

## Notes

- Always backup files before migration or use `--check` first
- oklch colors may look slightly different than hex - verify visually
- Some v3 plugins may not have v4 equivalents yet
- Test thoroughly after migration, especially dark mode and responsive designs
