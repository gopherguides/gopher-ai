---
argument-hint: "[--check]"
description: "Migrate Tailwind CSS v3 configuration to v4 CSS-based config"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(npm:*)", "Bash(pnpm:*)", "Bash(yarn:*)", "Bash(bun:*)", "Bash(ls:*)", "Bash(grep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
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

For a workspace member, `package.json` means the requested member manifest and
the active lockfile means the verified owning workspace lockfile. Do not back
up or modify unrelated package manifests.

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

Bind the directory containing the selected v3 configuration and its application
integration to `<MIGRATION_TARGET>`. Starting there, walk only ancestor
directories and inspect package-manager ownership evidence without writing.
Find the nearest ancestor whose workspace configuration, such as `package.json`
`workspaces` or `pnpm-workspace.yaml`, actually includes `<MIGRATION_TARGET>`.
Bind that verified owner to `<PACKAGE_ROOT>` and the requested member's concrete
package name or root-relative path to `<WORKSPACE_MEMBER>`. For a standalone
project, `<PACKAGE_ROOT>` and `<MIGRATION_TARGET>` are the same directory.

At `<PACKAGE_ROOT>`, read the `packageManager` field and inspect
`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, and `bun.lockb`.
Use the declared manager when it agrees with the owning lockfile. Otherwise,
use the single owning lockfile already present. Treat competing ownership
roots, a member declaration that disagrees with its owning root, multiple
manager lockfiles, or a workspace that does not clearly include the migration
target as conflicting signals. Ask which root and manager are authoritative
and stop before changing dependencies. If no ownership evidence exists at the
target or any ancestor, bind `<PACKAGE_ROOT>` to `<MIGRATION_TARGET>` and
default to npm.

Use the selected manager consistently:

| Manager | Remove dependencies | Add development dependencies | Run a script |
|---------|---------------------|------------------------------|--------------|
| npm | `npm uninstall <PACKAGES>` | `npm install -D <PACKAGES>` | `npm run <SCRIPT>` |
| pnpm | `pnpm remove <PACKAGES>` | `pnpm add -D <PACKAGES>` | `pnpm run <SCRIPT>` |
| Yarn | `yarn remove <PACKAGES>` | `yarn add -D <PACKAGES>` | `yarn run <SCRIPT>` |
| Bun | `bun remove <PACKAGES>` | `bun add -d <PACKAGES>` | `bun run <SCRIPT>` |

Do not create a lockfile for a different package manager.
When `<PACKAGE_ROOT>` equals `<MIGRATION_TARGET>`, run the selected package
manager there normally. For a workspace member, run every dependency and
script command from `<PACKAGE_ROOT>` with that manager's explicit member
selector bound to `<WORKSPACE_MEMBER>`. Never run an unscoped dependency or
script command at the workspace root for a member migration. Verify that only
the requested member manifest and owning lockfile receive dependency changes;
never create a member-level or different-ancestor lockfile.

## Step 2: Parse v3 Configuration

Read the config file without evaluating untrusted JavaScript. Extract: content
configuration (becomes `@source` directives), direct `theme` namespace
replacements, `theme.extend`, `safelist`, `prefix`, `separator`, `corePlugins`,
`presets`, `darkMode` (becomes a custom variant and selector), `important`, and
`plugins` (check v4 compatibility).

Support both v3 content forms:

- For `content: [...]`, use the array entries and the project invocation root
  as their effective base.
- For `content: { files: [...], relative: true }`, parse `content.files` and
  use the directory containing the v3 configuration as the effective base.
- For object-form content with `content.relative` false or absent, use the
  project invocation root as the effective base.
- Treat raw-content objects separately from file globs and apply the lossless
  conversion gate below. Never drop them or pass them to `@source` as paths.

### Preset Chain Preservation

Parse `presets` independently and preserve their declared order and override
precedence. Recursively resolve a preset only when every link is a statically
readable local object or data file that can be inspected without executing
JavaScript. Feed every inherited content, theme, plugin, core-plugin, prefix,
separator, safelist, dark-mode, important, and nested-preset value through the
same lossless conversion gates as the project config.

Do not partially migrate a preset chain. Treat an external package export,
function, computed import, conditional value, cycle, unreadable link, or any
inherited field that cannot be resolved and converted losslessly as an
unresolved preset chain. Retain the v3 configuration and every local preset
file unchanged, report the first unresolved link and all affected inherited
fields, and block migration completion and config removal. Retaining or
loading the JavaScript config is not proof that all preset semantics survived
the v4 conversion.

Before clearing the blocker, compare the fully resolved effective v3
configuration with the proposed v4 configuration and verify the generated
utility and behavior sets, including preset-provided plugins and disabled core
features. A successful build alone is insufficient.

### Raw Content Preservation

For every v3 `{ raw: <CONTENT>, extension: <TYPE> }` content entry, parse the
raw value only when it is a static string. Enumerate the exact complete class
candidates that the project's v3 scanner derives from that string, including
variants and arbitrary values. Emit one safely escaped `@source inline()` input
for each exact candidate, or use brace expansion only when its fully expanded
set is provably identical.

Prove equivalence by comparing the complete candidate and generated-utility
sets for the isolated v3 raw entry with the proposed v4 inline sources. A
successful build alone is insufficient. Do not infer candidates from dynamic
JavaScript, interpolation, concatenation, a computed raw value, or an extractor
whose v3 behavior cannot be reproduced exactly.

If exact equivalence cannot be proven, retain the configuration at its original
path, add the rebased `@config` directive when it remains useful for supported
fields, and report the raw entry as unresolved. Retaining the JavaScript config
through `@config` alone is not proof that raw-content semantics are equivalent
in v4. Block configuration removal and migration completion until an explicit
v4 source produces the same utility set.

### Prefix Preservation

Parse the v3 `prefix` value and inventory every prefixed utility in source
files, raw content, safelist entries, `@apply`, and plugin-generated usage. For
a static v3 prefix of the form `<PREFIX>-` that is accepted by v4, remove the
trailing hyphen and configure the single Tailwind import with `prefix()`:

```css
@import "tailwindcss" prefix(<PREFIX>);
```

Compose `prefix()` on the same legal import as other modifiers. For example,
boolean important plus prefix becomes:

```css
@import "tailwindcss" prefix(<PREFIX>) important;
```

V4 prefixes are variant-like and must lead the complete utility. Rewrite only
confirmed Tailwind tokens, preserving their variant, negative, arbitrary, and
important semantics. Examples include `tw-flex` to `tw:flex`,
`hover:tw-bg-red-500` to `tw:hover:bg-red-500`, and `-tw-mt-4` to
`tw:-mt-4`. Do not perform substring replacement in ordinary text or custom
class names.

Before writing, enumerate the old and proposed prefixed utility sets. When
builds are allowed, verify every migrated token produces the corresponding v4
selector and equivalent declarations. If the prefix is computed, invalid for
v4, dynamically assembled, or otherwise cannot be rewritten and verified
losslessly, retain the config, report the prefix migration as unresolved, and
block completion. Do not assume that JavaScript `@config` alone preserves v3
`prefix` behavior; keep the blocker until exact generated behavior is
verified.

### Custom Separator Preservation

Parse the v3 `separator` independently of `prefix`, including when no prefix
is configured. The default `:` separator needs no rewrite. For a static custom
separator, inventory every confirmed v3 separator-form Tailwind token in
source files, raw content, safelist entries, `@apply`, and plugin-generated
usage. Rewrite each complete confirmed token to v4's `:` variant separator
while preserving prefix, variant order, negative, arbitrary, and important
semantics. Do not replace separator characters in ordinary text, arbitrary
values, URLs, custom class names, or dynamically assembled candidates.

Before writing, enumerate the complete old and proposed candidate sets from
every location. When builds are allowed, compare the generated selector and
declaration sets for every rewritten token and require exact equivalence. If
the separator is computed, a token is ambiguous or dynamic, plugin output
cannot be enumerated, or generated equivalence cannot be proven, retain the
configuration unchanged, report separator migration as unresolved, and block
completion and config removal. V4 `@config` does not support `separator`, so
retaining or loading the JavaScript config is not evidence that custom
separator behavior survived.

### Direct Theme Namespace Replacements

Distinguish direct `theme.<namespace>` values from
`theme.extend.<namespace>`. A direct v3 namespace replaces Tailwind's defaults;
it is not an extension. Reproduce that replacement by resetting the complete
matching v4 namespace before emitting its translated values. For example:

```css
@theme {
  --color-*: initial;
  --color-brand: #3b82f6;
}
```

Use the corresponding v4 namespace wildcard for every direct replacement,
such as `--color-*`, `--font-*`, `--spacing-*`, `--radius-*`, or
`--breakpoint-*`. An empty direct namespace still emits its reset. When both a
direct namespace and `theme.extend` target the same namespace, emit one reset,
then the direct values, then the extension values so the final variables match
v3 merge and override semantics. Do not reset namespaces that appear only
under `theme.extend`.

Translate a direct namespace only when every key and value can be represented
losslessly as v4 theme variables. If a computed value, function, imported
object, or unsupported namespace cannot be translated losslessly, do not emit
a partial reset for that namespace. Add this directive using a path rebased
from `<CSS_ENTRY>`, retain the configuration at its original path, and record
the namespace as unresolved:

```css
@config "<RELATIVE_CONFIG_PATH>";
```

Do not remove or rename a configuration referenced by `@config`. Do not report
the migration as complete until every unresolved direct theme replacement is
preserved by a verified alternative.

### Core Plugin Preservation

Parse every v3 `corePlugins` setting. The lossless supported disabled-plugin
mapping is `corePlugins: { preflight: false }`. Replace the combined Tailwind
import with the official v4 split imports and omit only the preflight import:

```css
@layer theme, base, components, utilities;
@import "tailwindcss/theme.css" layer(theme);
@import "tailwindcss/utilities.css" layer(utilities);
```

Compose existing import modifiers on the split imports according to what they
affect. Apply `prefix(<PREFIX>)` to both the theme and utilities imports. Apply
`source(...)` and boolean `important` only to the utilities import. For example,
prefix plus boolean important becomes:

```css
@layer theme, base, components, utilities;
@import "tailwindcss/theme.css" layer(theme) prefix(<PREFIX>);
@import "tailwindcss/utilities.css" layer(utilities) prefix(<PREFIX>) important;
```

Do not emit `@import "tailwindcss/preflight.css" layer(base);` when preflight is
disabled. Preserve every unrelated import and keep all generated imports in
CSS's legal import region.

Any other disabled core plugin, array-form allowlist, computed `corePlugins`
value, or combination that cannot be represented with verified v4 CSS is
unresolved. Keep the v3 configuration unchanged, report each unsupported
setting, and block migration completion and config removal. JavaScript
`@config` does not support `corePlugins` in v4, so retaining or loading the
config is not evidence that the disabled behavior survived.

### Safelist Preservation

Parse every v3 `safelist` entry independently of content-file matches. For each
literal class string, emit an escaped v4 inline source that represents the
same complete class:

```css
@source inline("<LITERAL_CLASS>");
```

A finite statically enumerable group may use v4 brace expansion only after
expanding it and proving that its class and variant set exactly equals the v3
safelist entries. Do not guess an expansion for regular expressions, pattern
objects, computed entries, or variant generation that cannot be enumerated
losslessly.

When any safelist entry cannot be translated losslessly, retain the v3
configuration, add its rebased `@config` directive if not already present, and
report the unsupported safelist entry as unresolved. Retaining `@config` does
not make unsupported v4 safelist semantics equivalent, so do not remove the
configuration or report the migration complete until generated utility
coverage is preserved by an explicit v4 alternative.

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

Identify every Tailwind CSS entry that a build integration compiles
independently and bind the complete set to `<CSS_ENTRIES>`. Bind the entry used
by the selected primary build command to `<CSS_ENTRY>`. Distinguish independent
entries from CSS fragments using package scripts and Vite, PostCSS, or other
build configuration; ask before writing when repository evidence cannot
disambiguate them.

For the CLI integration, derive a distinct sibling output path and bind it to `<CSS_OUTPUT>`: replace an `input.css` filename with `output.css`, or append
`.generated.css` to another stem. Never use `<CSS_ENTRY>` itself as output.

Determine the effective base directory for every v3 `content` pattern using
the v3 configuration and project invocation context. For every entry in
`<CSS_ENTRIES>`, rebase every content glob from that base to the directory
containing that entry before emitting an `@source` directive. Normalize path
separators to `/` and preserve glob syntax. For example, with `src/index.css`
and a project-root v3 base, `./src/**/*.tsx` becomes `./**/*.tsx`, while
`./public/**/*.html` becomes `../public/**/*.html`.

Enumerate the files matched before and after rebasing. Do not write or report a
migration as complete unless the generated `@source` directives from every
independently built entry resolve to the same files as the v3 content patterns.

### Boolean `important`

When the v3 configuration sets `important: true`, preserve that behavior by
adding `important` to the selected import, including an existing `prefix()` or
`source()` modifier. Without other modifiers, use:

```css
@import "tailwindcss" important;
```

When `important` is false or absent, keep `@import "tailwindcss";`.

### Selector-form `important`

A v3 selector value such as `important: "#app"` scopes utilities instead of
adding `!important`, and v4 has no equivalent selector option on the Tailwind
import. Do not translate a selector value to the boolean `important` import.
In normal migration mode, stop before deleting the old configuration and ask
whether to adopt the broader boolean behavior or leave selector scoping as a
documented manual migration item. In `--check`, report the unresolved choice
without changing files. Do not complete until the selected alternative is
implemented and its cascade behavior is verified.

Convert the parsed configuration to v4 CSS:

```css
@import "tailwindcss";

/* Rebased from content array relative to <CSS_ENTRY> */
@source "<REBASED_CONTENT_PATH>";

/* Literal v3 safelist entry */
@source inline("<LITERAL_CLASS>");

/* Direct theme.colors replacement followed by theme.extend */
@theme {
  --color-*: initial;
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

Generate an equivalent converted configuration block for every independently
built entry before editing any entry. Rebase entry-relative `@source` and
`@config` paths separately for each entry. Read every original entry in
`<CSS_ENTRIES>` completely and merge its block in place. Read the entire
original `<CSS_ENTRY>` and merge that block for the primary entry. Never
replace the entire CSS entry with the generated block; apply this preservation
rule to every entry.

During the merge:

1. Replace only the three legacy `@tailwind base;`,
   `@tailwind components;`, and `@tailwind utilities;` directive spans. Insert
   the selected Tailwind import or split-import set where the first legacy directive appeared when
   that location is still in CSS's legal import region. Otherwise, insert it
   after any `@charset` and existing imports but before the first ordinary rule
   or non-import at-rule, without moving existing content. Remove the other
   legacy directive spans. If the entry already has the equivalent Tailwind
   import or equivalent split-import set, remove the legacy spans without
   adding duplicate imports.
2. Insert the converted `@source`, `@source inline()`, `@theme`, `@config`,
   `@custom-variant`, dark selector, and `@plugin` configuration adjacent to
   that import. Merge generated
   declarations into compatible existing v4 blocks and preserve existing
   declarations. Deduplicate exact directives; if an existing declaration has
   the same name but a different value, stop and ask which value is
   authoritative before writing.
3. Preserve every custom import, `@layer` block, `@apply` rule, at-rule,
   comment, and ordinary CSS rule in its original order. Do not rewrite,
   relocate, or discard non-legacy content.

Before writing, compare the original and proposed content with the three
legacy directive spans and newly generated configuration excluded. Do not
write unless the remaining existing content is identical and in the same
order.

With `--check`, render every proposed merged CSS entry or an exact diff in the
report without writing it. Otherwise, apply the verified in-place merges to
all entries only after every proposed entry passes the preservation checks.

## Step 4: Update CSS Files

```bash
grep -rl '@tailwind' --include="*.css" .
```

Replace v3 directives:

| v3 | v4 |
|----|-----|
| `@tailwind base;` / `components;` / `utilities;` (any/all) | `@import "tailwindcss";` |

Existing `@apply` rules in your CSS continue to work unchanged.

For every independently built entry in `<CSS_ENTRIES>`, place the equivalent
selected Tailwind import or split-import set in the legal import region and
merge that entry's complete converted configuration block adjacent to it.
Never omit converted configuration merely because an entry is secondary. For
every affected CSS fragment that is not independently built, use the same
directive-only replacement: place the equivalent import or split-import set at
the first legacy directive, remove only the remaining legacy directive spans,
and preserve all custom imports, `@layer` blocks, comments, at-rules, and
ordinary CSS.

Preserve entry-specific CSS and relative order in every entry. Build and
verify every independent entry through its actual integration, compare the
generated utility sets with v3, and require equivalent configuration behavior
before allowing old-config removal. If any independent entry cannot receive
and build the complete equivalent configuration, retain the old configuration
and block migration completion.

With `--check`, list every affected CSS file and show its proposed in-place
replacement without editing it. Otherwise, apply the verified replacements.

## Step 5: Update package.json

With `--check`, report the dependencies and scripts that would be removed,
added, or changed. Do not run a package manager or edit `package.json`.

Without `--check`, apply the matching integration method below.

Apply every dependency and script change to the requested member manifest.
When it is a workspace member, use the selected manager's explicit
`<WORKSPACE_MEMBER>` selector from `<PACKAGE_ROOT>` so the owning lockfile is
updated without changing an unrelated package or creating a member lockfile.

**CLI method (recommended for most projects):**

Remove `tailwindcss` and any PostCSS packages used exclusively by the old
Tailwind integration, then add
`tailwindcss@latest @tailwindcss/cli@latest` with the selected package manager.
Preserve PostCSS dependencies that other project tooling still uses.

Scripts:

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
file unchanged as required by the Preservation Flags section.

Before offering any disposition, check preset chains, direct theme
replacements, safelist entries, raw content, prefix, separator, core plugins,
plugins, and every other parsed configuration field for unresolved semantics.
If any field or preset link is unresolved or `<CSS_ENTRY>` contains `@config`,
keep the configuration and all referenced local preset files unchanged, report
why they remain required, and do not offer deletion or rename. Otherwise, use
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

Verify that each direct theme namespace has the required wildcard reset and
that its resolved variables reproduce the v3 namespace. Verify that every
literal safelist entry is represented by an equivalent `@source inline()` and,
when builds are allowed, generates the expected utility. Treat any unresolved
theme or safelist conversion as a migration blocker even when the build exits
successfully.

Verify every raw content entry has an exactly equivalent candidate and utility
set from its v4 inline sources. When a v3 prefix exists, verify the Tailwind
import contains the correct `prefix()` modifier and every migrated source token
uses the prefix-first v4 form and generates its expected selector. Treat either
unresolved conversion as a blocker even when the build succeeds.

When `corePlugins.preflight` is false, verify the final CSS uses the split
theme and utilities imports, contains no preflight import, still generates
expected utilities, and omits representative preflight reset behavior. For any
other disabled core plugin, keep the migration unresolved until equivalent
generated behavior is demonstrated; a successful v4 build is insufficient.

Verify the recursively resolved effective preset configuration matches the
proposed v4 configuration and generated behavior. Keep any unreadable,
external, computed, cyclic, partial, or behaviorally mismatched preset chain
as an unresolved blocker even when the selected build succeeds.

Without `--check`, run only the verification path for the selected integration.

### CLI Verification

Run the configured CLI build and confirm its output file exists and is
non-empty:

Run the `css` script with the selected package manager, for example `npm run
css`, `pnpm run css`, `yarn run css`, or `bun run css`. For a workspace member,
run it from `<PACKAGE_ROOT>` with the explicit `<WORKSPACE_MEMBER>` selector.
Inspect the first 20 output lines. Confirm the concrete `<CSS_OUTPUT>` exists
and is non-empty and belongs to `<MIGRATION_TARGET>`.

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
- W safelist entries → @source inline() directives
- R raw content entries → verified @source inline() directives
- Prefix/separator → import modifier plus migrated utility tokens
- Core plugins → split imports without preflight, or retained unresolved config
- Presets → recursively resolved and migrated, or retained unresolved chain
- Z plugins → @plugin directives
- Dark mode → class-based custom variant plus `.dark` overrides
- tailwind.config.js — removed (or kept per user choice)
- Backups — [created paths, not requested, or preview only]

### Manual Review Needed
- [ ] Verify custom colors look correct
- [ ] Test dark mode toggle
- [ ] Check responsive breakpoints
- [ ] Verify plugins work correctly
- [ ] Resolve any retained direct theme namespace or safelist conversion
- [ ] Resolve any retained raw content or prefix conversion
- [ ] Resolve unsupported disabled core plugins
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
3. The preview report identifies unresolved preset, plugin, core plugin, theme namespace, safelist, raw content, prefix, separator, or color conversions
4. Proposed `@source` paths preserve the v3 content matches from every independently built CSS entry
5. Boolean or selector-form `important` behavior is preserved or identified as an unresolved choice
6. Direct theme resets and literal safelist inline sources preserve v3 semantics or are identified as unresolved
7. Raw content, prefix, and separator semantics are preserved or identified as unresolved blockers
8. Disabled core-plugin behavior is preserved or identified as an unresolved blocker
9. Every independently built entry would receive equivalent converted configuration while preserving its entry-specific CSS and order
10. Package-manager ownership and workspace-member scoping were resolved without mutation
11. No project files, dependencies, or generated CSS changed

Without `--check`, follow the selected integration path. Use only the migration completion criteria for the selected integration.

### CLI Migration Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. v3 config parsed and analyzed
2. CSS file updated with the selected combined or split Tailwind imports and `@theme`
3. `tailwindcss` and `@tailwindcss/cli` updated to v4
4. CLI build scripts added to `package.json`
5. The selected package manager's `css` script succeeds and generates non-empty output CSS at `<CSS_OUTPUT>`
6. No `@tailwind` directives remain in CSS files
7. Every detected plugin dependency is installed and referenced by its generated `@plugin` directive
8. Requested `--backup` and `--keep-config` behavior completed before destructive changes
9. Generated `@source` directives preserve every v3 content match relative to every independently built CSS entry
10. v3 `important` behavior is preserved and verified
11. Every direct theme namespace replacement is translated with its reset semantics or remains unresolved with the config retained
12. Every safelist entry is translated losslessly to `@source inline()` or remains unresolved with the config retained
13. The old configuration was not removed or renamed while any parsed field remained unresolved or referenced by `@config`
14. Every raw content entry has an exactly equivalent v4 inline source or remains unresolved with the config retained
15. The v3 prefix import and every prefixed utility are migrated and verified losslessly or remain unresolved with the config retained
16. `corePlugins.preflight: false` uses verified split imports without preflight, and every other disabled core plugin remains unresolved with the config retained
17. Every custom-separator token is rewritten to v4 colon form with generated equivalence verified, or remains unresolved with the config retained
18. Every independently built CSS entry contains equivalent converted configuration, preserves its entry-specific CSS and order, and passes its actual build
19. Every preset chain is fully resolved and migrated with equivalent generated behavior, or remains unresolved with the config and local preset files retained
20. Workspace dependency and script commands explicitly target `<WORKSPACE_MEMBER>` from `<PACKAGE_ROOT>`, or the standalone project owns its manager locally

### PostCSS Migration Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. v3 config parsed and analyzed
2. CSS file updated with the selected combined or split Tailwind imports and `@theme`
3. `tailwindcss`, `@tailwindcss/postcss`, and `postcss` updated to v4
4. `@tailwindcss/postcss` registered in the PostCSS configuration
5. CSS entry connected to the existing PostCSS pipeline
6. Existing PostCSS-backed build succeeds with zero errors
7. No CLI-only `css` script was added solely for migration verification
8. No `@tailwind` directives remain in CSS files
9. Every detected plugin dependency is installed and referenced by its generated `@plugin` directive
10. Requested `--backup` and `--keep-config` behavior completed before destructive changes
11. Generated `@source` directives preserve every v3 content match relative to every independently built CSS entry
12. v3 `important` behavior is preserved and verified
13. Every direct theme namespace replacement is translated with its reset semantics or remains unresolved with the config retained
14. Every safelist entry is translated losslessly to `@source inline()` or remains unresolved with the config retained
15. The old configuration was not removed or renamed while any parsed field remained unresolved or referenced by `@config`
16. Every raw content entry has an exactly equivalent v4 inline source or remains unresolved with the config retained
17. The v3 prefix import and every prefixed utility are migrated and verified losslessly or remain unresolved with the config retained
18. `corePlugins.preflight: false` uses verified split imports without preflight, and every other disabled core plugin remains unresolved with the config retained
19. Every custom-separator token is rewritten to v4 colon form with generated equivalence verified, or remains unresolved with the config retained
20. Every independently built CSS entry contains equivalent converted configuration, preserves its entry-specific CSS and order, and passes its actual build
21. Every preset chain is fully resolved and migrated with equivalent generated behavior, or remains unresolved with the config and local preset files retained
22. Workspace dependency and script commands explicitly target `<WORKSPACE_MEMBER>` from `<PACKAGE_ROOT>`, or the standalone project owns its manager locally

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
