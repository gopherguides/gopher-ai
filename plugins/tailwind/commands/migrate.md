---
argument-hint: "[--check]"
description: "Migrate Tailwind CSS v3 configuration to v4 CSS-based config"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(npm:*)", "Bash(pnpm:*)", "Bash(yarn:*)", "Bash(bun:*)", "Bash(ls:*)", "Bash(grep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_config_guide"]
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
| `darkMode: 'class'` | `@custom-variant dark (...)` plus `.dark { }` overrides |
| `theme.extend.colors` | `--color-*` CSS variables |

Proceed with migration.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- `--check` — preview changes without modifying files
- `--keep-config` — keep old config file after migration (for reference)
- `--backup` — create backup files before modifying

## Read-only Preview (`--check`)

When `--check` is present, capture the initial repository status, then follow
Steps 1-3 to analyze the v3 project and generate proposed v4 content in the
response. In Steps 4-7, describe the exact file, package, and configuration
changes that normal migration mode would make without applying them.

Do not edit files, install or remove dependencies, rename or delete configuration, or run a build that overwrites generated CSS. Skip mutation-specific questions and record the recommended old-config disposition as a preview item instead. Use the Preview Completion Criteria at the end of this workflow rather than the mutation criteria.

Without `--check`, perform the migration and use the Migration Completion
Criteria.

## Preservation Flags

When `--backup` is present and `--check` is absent, create backups before the
first mutation. Back up every file that the migration will modify or remove,
including affected CSS, `package.json`, the active lockfile, PostCSS
configuration, and the v3 Tailwind configuration. Use a
`.tailwind-v3.bak` suffix and a numbered suffix when that path already exists.
Record every source-to-backup mapping. If any backup fails, stop before making
changes.

With `--check --backup`, report the backup paths that a normal migration would
create without writing them.

When `--keep-config` is present, keep the old Tailwind configuration unchanged
after migration and state that v4 does not auto-detect it. Do not ask how to dispose of the old configuration. With `--check --keep-config`, record that disposition in the preview without changing the file.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-migrate" "COMPLETE"; fi`

## Step 1: Find v3 Configuration

```bash
ls tailwind.config.js tailwind.config.ts tailwind.config.cjs tailwind.config.mjs 2>/dev/null
grep '"tailwindcss"' package.json 2>/dev/null
ls package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb 2>/dev/null
```

If no config found:

> No `tailwind.config.*` file found. Options: (1) project may already use v4 (CSS-based config); (2) use `/tailwind-init` to set up v4 from scratch; (3) check if config is in a non-standard location.

## Package Manager Selection

Read the `packageManager` field in `package.json` and inspect
`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, and `bun.lockb`.
Use the declared manager when it agrees with the lockfile. Otherwise, use the
single lockfile already present. If the signals conflict, ask which manager is
authoritative and stop before changing dependencies. If neither signal exists,
default to npm.

Use the selected manager consistently:

| Manager | Remove dependencies | Add development dependencies | Run a script |
|---------|---------------------|------------------------------|--------------|
| npm | `npm uninstall <PACKAGES>` | `npm install -D <PACKAGES>` | `npm run <SCRIPT>` |
| pnpm | `pnpm remove <PACKAGES>` | `pnpm add -D <PACKAGES>` | `pnpm run <SCRIPT>` |
| Yarn | `yarn remove <PACKAGES>` | `yarn add -D <PACKAGES>` | `yarn run <SCRIPT>` |
| Bun | `bun remove <PACKAGES>` | `bun add -d <PACKAGES>` | `bun run <SCRIPT>` |

Do not create a lockfile for a different package manager.

## Step 2: Parse v3 Configuration

Read the config file. Extract: `content` array (becomes `@source` directives), `theme.extend` (becomes `@theme` CSS variables), `darkMode` (becomes a custom variant and selector), `plugins` (check v4 compatibility).

**Plugin compatibility:**

| v3 Plugin | v4 Status |
|-----------|-----------|
| `@tailwindcss/forms` | Preserve/install the package; add `@plugin "@tailwindcss/forms";` |
| `@tailwindcss/typography` | Preserve/install the package; add `@plugin "@tailwindcss/typography";` |
| `@tailwindcss/container-queries` | Built-in (not needed) |
| `@tailwindcss/aspect-ratio` | Built-in (not needed) |

Preserve plugin options when converting them. For example, migrate the forms
plugin's `strategy` option into an `@plugin` block instead of dropping it.

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
@custom-variant dark (&:where(.dark, .dark *));

.dark { /* override theme colors here if needed */ }

/* Plugins */
@plugin "@tailwindcss/forms";
@plugin "@tailwindcss/typography";
```

Emit only the plugin directives detected in the v3 configuration.

For hex → oklch conversion, use https://oklch.com/. Common conversions:

| Hex | oklch |
|-----|-------|
| `#3b82f6` (blue-500) | `oklch(0.59 0.2 250)` |
| `#ef4444` (red-500) | `oklch(0.63 0.26 25)` |
| `#22c55e` (green-500) | `oklch(0.72 0.19 145)` |
| `#f59e0b` (amber-500) | `oklch(0.75 0.18 70)` |
| `#ffffff` / `#000000` | `oklch(1 0 0)` / `oklch(0 0 0)` |

With `--check`, render this proposed CSS in the report without writing it.
Otherwise, write it to the selected CSS entry file.

## Step 4: Update CSS Files

```bash
grep -rl '@tailwind' --include="*.css" .
```

Replace v3 directives:

| v3 | v4 |
|----|-----|
| `@tailwind base;` / `components;` / `utilities;` (any/all) | `@import "tailwindcss";` |

Existing `@apply` rules in your CSS continue to work unchanged.

With `--check`, list every affected CSS file and its proposed replacements but
do not edit it. Otherwise, apply the replacements.

## Step 5: Update package.json

With `--check`, report the dependencies and scripts that would be removed,
added, or changed. Do not run a package manager or edit `package.json`.

Without `--check`, apply the matching integration method below.

**CLI method (recommended for most projects):**

Remove `tailwindcss` and any PostCSS packages used exclusively by the old
Tailwind integration, then add
`tailwindcss@latest @tailwindcss/cli@latest` with the selected package manager.
Preserve PostCSS dependencies that other project tooling still uses.

Scripts:

```json
{
  "scripts": {
    "css": "tailwindcss -i ./src/input.css -o ./src/output.css --minify",
    "css:watch": "tailwindcss -i ./src/input.css -o ./src/output.css --watch"
  }
}
```

**PostCSS method (if using an existing PostCSS pipeline):**

Remove the old `tailwindcss` package and `autoprefixer` only when it is not used
elsewhere, then add
`tailwindcss@latest @tailwindcss/postcss@latest postcss` with the selected
package manager.

For every v3 plugin converted to an `@plugin` directive, preserve its package
in `devDependencies` and install a compatible version if it is missing. When
`@tailwindcss/forms` is detected and `--check` is not present, add
`@tailwindcss/forms@latest` with the selected package manager's development
dependency command.

With `--check`, report that package action without running it. Do not uninstall packages referenced by generated `@plugin` directives.

## Step 6: Handle PostCSS Config

With `--check`, include the proposed configuration in the report without
writing it. Otherwise, update the existing PostCSS configuration when the
project uses that integration.

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

With `--check`, report the recommended disposition and available alternatives
without renaming or deleting the existing file. With `--keep-config`, keep the
file unchanged as required by the Preservation Flags section. Otherwise, use
`AskUserQuestion`: "Migration complete. What should we do with `tailwind.config.js`?"

| Option | Description |
|--------|-------------|
| **Delete** (recommended) | Config is now in CSS |
| **Keep as backup** | Rename to `tailwind.config.js.bak` |
| **Keep unchanged** | May cause confusion |

## Step 8: Verify

With `--check`, verify that the proposed CSS contains the v4 import and theme
directives, the proposed package set targets v4, and the final repository
status matches the initial status. Do not run the CSS build because it may
overwrite generated output.

Without `--check`, run only the verification path for the selected integration.

### CLI Verification

Run the configured CLI build and confirm its output file exists and is
non-empty:

Run the `css` script with the selected package manager, for example
`npm run css`, `pnpm run css`, `yarn run css`, or `bun run css`, and inspect the
first 20 output lines.

### PostCSS Verification

Confirm the migrated CSS entry is connected to the existing PostCSS pipeline,
then run that pipeline's existing build command. Verify it succeeds with
`@tailwindcss/postcss` enabled. Do not add or invoke a CLI-only `css` script.

If the PostCSS project has no build command, report the missing project-level
command and ask which existing command should verify the integration rather
than silently adding a CLI workflow.

Common errors:

| Error | Solution |
|-------|----------|
| `Unknown directive @tailwind` | Old directive not removed |
| `Cannot find module` | Plugin not v4 compatible |
| `Invalid CSS` | Syntax error in `@theme` block |

## Step 9: Migration or Preview Report

With `--check`, label the report `Tailwind v3 → v4 Migration Preview`, describe
all proposed changes and unresolved choices, and state that no project files or
dependencies were changed. Otherwise, use the completion report below.

```
## Tailwind v3 → v4 Migration Complete

### Changes
- [CSS file] — @import + @theme
- package.json — v4 dependencies
- [postcss.config.js] — updated (if applicable)
- X custom colors → @theme variables
- Y content paths → @source directives
- Z plugins → @plugin directives
- Dark mode → class-based custom variant plus `.dark` overrides
- tailwind.config.js — removed (or kept per user choice)
- Backups — [created paths, not requested, or preview only]

### Manual Review Needed
- [ ] Verify custom colors look correct
- [ ] Test dark mode toggle
- [ ] Check responsive breakpoints
- [ ] Verify plugins work correctly
```

Use only the next steps for the selected integration.

### CLI Migration Next Steps

1. Run the `css:watch` script with the selected package manager
2. Test the generated stylesheet thoroughly
3. Run `/tailwind-audit` to check for any issues
4. Commit

### PostCSS Migration Next Steps

1. Run the existing PostCSS-backed development or watch command
2. Test the stylesheet produced by the project's asset pipeline thoroughly
3. Run `/tailwind-audit` to check for any issues
4. Commit

Resources: https://tailwindcss.com/docs/upgrade-guide; https://oklch.com/

## Notes

- Always backup files before migration or use `--check` first
- oklch colors may look slightly different than hex — verify visually
- Some v3 plugins may not have v4 equivalents yet
- Test thoroughly after migration, especially dark mode and responsive designs

## Completion Criteria

### Preview Completion Criteria

When `--check` is present, do not output `<done>COMPLETE</done>` until ALL of
these are TRUE:

1. The v3 configuration and affected CSS files were parsed and analyzed
2. Proposed CSS, dependency, script, PostCSS, and old-config changes were shown
3. The preview report identifies unresolved plugin or color conversions
4. No project files, dependencies, or generated CSS changed

Without `--check`, follow the selected integration path. Use only the migration completion criteria for the selected integration.

### CLI Migration Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. v3 config parsed and analyzed
2. CSS file updated with `@import "tailwindcss"` and `@theme`
3. `tailwindcss` and `@tailwindcss/cli` updated to v4
4. CLI build scripts added to `package.json`
5. The selected package manager's `css` script succeeds and generates non-empty output CSS
6. No `@tailwind` directives remain in CSS files
7. Every detected plugin dependency is installed and referenced by its generated `@plugin` directive
8. Requested `--backup` and `--keep-config` behavior completed before destructive changes

### PostCSS Migration Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. v3 config parsed and analyzed
2. CSS file updated with `@import "tailwindcss"` and `@theme`
3. `tailwindcss`, `@tailwindcss/postcss`, and `postcss` updated to v4
4. `@tailwindcss/postcss` registered in the PostCSS configuration
5. CSS entry connected to the existing PostCSS pipeline
6. Existing PostCSS-backed build succeeds with zero errors
7. No CLI-only `css` script was added solely for migration verification
8. No `@tailwind` directives remain in CSS files
9. Every detected plugin dependency is installed and referenced by its generated `@plugin` directive
10. Requested `--backup` and `--keep-config` behavior completed before destructive changes

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
