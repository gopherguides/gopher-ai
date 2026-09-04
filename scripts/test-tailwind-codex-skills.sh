#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PLUGIN_DIR="$ROOT_DIR/plugins/tailwind"
ADAPTER="$PLUGIN_DIR/lib/codex-command-adapter.md"
WORKFLOW_SKILLS=(audit init migrate optimize)
EXPLICIT_SKILLS=(init migrate)
DISCOVERABLE_SKILLS=(audit optimize)

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

if rg -n -i 'mcp' "$PLUGIN_DIR"; then
  fail "Tailwind plugin still references removed MCP tooling"
fi

frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit 1 }
    NR > 1 && /^---$/ { exit }
    NR > 1 { print }
  ' "$1"
}

assert_contains() {
  local file="$1"
  local text="$2"

  awk -v text="$text" 'index($0, text) { found = 1; exit } END { exit found ? 0 : 1 }' "$file" ||
    fail "${file#"$ROOT_DIR/"} is missing: $text"
}

assert_not_matches() {
  local file="$1"
  local pattern="$2"

  if awk -v pattern="$pattern" '$0 ~ pattern { found = 1; exit } END { exit found ? 0 : 1 }' "$file"; then
    fail "${file#"$ROOT_DIR/"} unexpectedly matches: $pattern"
  fi
}

matches() {
  local pattern="$1"

  awk -v pattern="$pattern" '$0 ~ pattern { found = 1; exit } END { exit found ? 0 : 1 }'
}

for skill_name in "${WORKFLOW_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  command_file="$PLUGIN_DIR/commands/$skill_name.md"
  [ -f "$skill_file" ] || fail "missing skill router: plugins/tailwind/skills/$skill_name/SKILL.md"
  [ -f "$command_file" ] || fail "missing command body: plugins/tailwind/commands/$skill_name.md"

  metadata=$(frontmatter "$skill_file") || fail "$skill_name has invalid frontmatter"
  printf '%s\n' "$metadata" | matches "^name: $skill_name$" || fail "$skill_name has the wrong frontmatter name"
  printf '%s\n' "$metadata" | matches '^description: .+' || fail "$skill_name is missing a description"
  assert_contains "$skill_file" '## Plugin Resource Resolution'
  assert_contains "$skill_file" 'directory containing the absolute selected'
  assert_contains "$skill_file" 'then ascend two directories'
  assert_contains "$skill_file" '<PLUGIN_ROOT>/lib/codex-command-adapter.md'
  assert_contains "$skill_file" "<PLUGIN_ROOT>/commands/$skill_name.md"
  assert_contains "$skill_file" 'Read both files completely'
done

for skill_name in "${EXPLICIT_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  policy_file="$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml"
  frontmatter "$skill_file" | matches '^disable-model-invocation: true$' || fail "$skill_name is not explicit-only"
  [ -f "$policy_file" ] || fail "$skill_name is missing agents/openai.yaml"
  matches '^  allow_implicit_invocation: false$' < "$policy_file" || fail "$skill_name policy allows implicit invocation"
done

for skill_name in "${DISCOVERABLE_SKILLS[@]}"; do
  skill_file="$PLUGIN_DIR/skills/$skill_name/SKILL.md"
  if frontmatter "$skill_file" | matches '^disable-model-invocation:'; then
    fail "$skill_name must remain auto-discoverable"
  fi
  [ ! -e "$PLUGIN_DIR/skills/$skill_name/agents/openai.yaml" ] || fail "$skill_name has an explicit-only policy"
done

[ -f "$ADAPTER" ] || fail "missing shared Codex command adapter"
for contract in \
  'SKILL_ARGS' \
  '$ARGUMENTS' \
  '${CLAUDE_PLUGIN_ROOT}' \
  '$tailwind:<skill-name>' \
  'skip every `Loop Initialization` section' \
  '`setup-loop.sh`' \
  '`<done>...</done>`' \
  'audit and optimize are read-only unless `--fix` is present' \
  'Do not modify project files, install dependencies, or overwrite generated CSS' \
  'bundled Tailwind references first'; do
  assert_contains "$ADAPTER" "$contract"
done
assert_contains "$ADAPTER" 'optimize binds it to `<OPTIMIZE_TARGET>`'
assert_contains "$ADAPTER" 'its explicit project path to `<INIT_TARGET>`.'
assert_contains "$ADAPTER" 'back to the current directory. Never broaden a target-scoped operation to the'

DARK_MODE_GUIDANCE=(
  "$PLUGIN_DIR/README.md"
  "$PLUGIN_DIR/commands/audit.md"
  "$PLUGIN_DIR/commands/init.md"
  "$PLUGIN_DIR/commands/migrate.md"
  "$PLUGIN_DIR/skills/tailwind-best-practices/SKILL.md"
  "$PLUGIN_DIR/skills/tailwind-best-practices/anti-patterns.md"
  "$PLUGIN_DIR/skills/tailwind-best-practices/v4-syntax.md"
)
for guidance_file in "${DARK_MODE_GUIDANCE[@]}"; do
  assert_not_matches "$guidance_file" '^@variant dark[[:space:]]*\\{'
done

for example_file in \
  "$PLUGIN_DIR/README.md" \
  "$PLUGIN_DIR/commands/init.md" \
  "$PLUGIN_DIR/commands/migrate.md" \
  "$PLUGIN_DIR/skills/tailwind-best-practices/v4-syntax.md"; do
  assert_contains "$example_file" '@custom-variant dark (&:where(.dark, .dark *));'
  assert_contains "$example_file" '.dark {'
done

MIGRATE_COMMAND="$PLUGIN_DIR/commands/migrate.md"
assert_contains "$MIGRATE_COMMAND" '## Read-only Preview (`--check`)'
assert_contains "$MIGRATE_COMMAND" 'Do not edit files, install or remove dependencies, rename or delete configuration, or run a build that overwrites generated CSS.'
assert_contains "$MIGRATE_COMMAND" '### Preview Completion Criteria'
assert_contains "$MIGRATE_COMMAND" 'No project files, dependencies, or generated CSS changed'
assert_contains "$MIGRATE_COMMAND" '| `@tailwindcss/forms` | Preserve/install the package; add `@plugin "@tailwindcss/forms";` |'
assert_contains "$MIGRATE_COMMAND" 'Do not uninstall packages referenced by generated `@plugin` directives.'
assert_contains "$MIGRATE_COMMAND" '## Preservation Flags'
assert_contains "$MIGRATE_COMMAND" 'When `--backup` is present and `--check` is absent'
assert_contains "$MIGRATE_COMMAND" 'When `--keep-config` is present'
assert_contains "$MIGRATE_COMMAND" 'Do not ask how to dispose of the old configuration'
assert_contains "$MIGRATE_COMMAND" '`<CSS_ENTRIES>`, rebase every content glob'
assert_contains "$MIGRATE_COMMAND" '`./src/**/*.tsx` becomes `./**/*.tsx`'
assert_contains "$MIGRATE_COMMAND" 'resolve to the same files as the v3 content patterns'
assert_contains "$MIGRATE_COMMAND" '`content.files`'
assert_contains "$MIGRATE_COMMAND" '`content.relative`'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss" important;'
assert_contains "$MIGRATE_COMMAND" '### Selector-form `important`'
assert_contains "$MIGRATE_COMMAND" 'Do not translate a selector value to the boolean `important` import.'
assert_contains "$MIGRATE_COMMAND" 'derive a distinct sibling output path and bind it to `<CSS_OUTPUT>`'
assert_contains "$MIGRATE_COMMAND" '"css": "tailwindcss -i <CSS_ENTRY> -o <CSS_OUTPUT> --minify"'
assert_contains "$MIGRATE_COMMAND" '`@config` paths separately for each entry. Read every original entry in'
assert_contains "$MIGRATE_COMMAND" 'original `<CSS_ENTRY>` and merge that block for the primary entry.'
assert_contains "$MIGRATE_COMMAND" 'original `<CSS_ENTRY>` and merge that block for the primary entry. Never'
assert_contains "$MIGRATE_COMMAND" 'replace the entire CSS entry with the generated block; apply this preservation'
assert_contains "$MIGRATE_COMMAND" 'Replace only the three legacy `@tailwind base;`'
assert_contains "$MIGRATE_COMMAND" "CSS's legal import region"
assert_contains "$MIGRATE_COMMAND" 'Preserve every custom import, `@layer` block, `@apply` rule, at-rule,'
assert_contains "$MIGRATE_COMMAND" 'apply the verified in-place merge'
assert_contains "$MIGRATE_COMMAND" '### Direct Theme Namespace Replacements'
assert_contains "$MIGRATE_COMMAND" '--color-*: initial;'
assert_contains "$MIGRATE_COMMAND" 'Do not reset namespaces that appear only'
assert_contains "$MIGRATE_COMMAND" '@config "<RELATIVE_CONFIG_PATH>";'
assert_contains "$MIGRATE_COMMAND" '### Safelist Preservation'
assert_contains "$MIGRATE_COMMAND" '@source inline("<LITERAL_CLASS>");'
assert_contains "$MIGRATE_COMMAND" 'v4 brace expansion only after'
assert_contains "$MIGRATE_COMMAND" 'regular expressions, pattern'
assert_contains "$MIGRATE_COMMAND" 'do not remove the'
assert_contains "$MIGRATE_COMMAND" 'while any parsed field remained unresolved or referenced by `@config`'
assert_contains "$MIGRATE_COMMAND" '### Raw Content Preservation'
assert_contains "$MIGRATE_COMMAND" 'raw value only when it is a static string. Enumerate the exact complete class'
assert_contains "$MIGRATE_COMMAND" "candidates that the project's v3 scanner derives from that string"
assert_contains "$MIGRATE_COMMAND" 'comparing the complete candidate and generated-utility'
assert_contains "$MIGRATE_COMMAND" 'through `@config` alone is not proof that raw-content semantics are equivalent'
assert_contains "$MIGRATE_COMMAND" '### Prefix Preservation'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss" prefix(<PREFIX>);'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss" prefix(<PREFIX>) important;'
assert_contains "$MIGRATE_COMMAND" '`tw-flex` to `tw:flex`'
assert_contains "$MIGRATE_COMMAND" '`hover:tw-bg-red-500` to `tw:hover:bg-red-500`'
assert_contains "$MIGRATE_COMMAND" 'verify every migrated token produces the corresponding v4'
assert_contains "$MIGRATE_COMMAND" '### Custom Separator Preservation'
assert_contains "$MIGRATE_COMMAND" '`safelist`, `prefix`, `separator`, `corePlugins`'
assert_contains "$MIGRATE_COMMAND" 'Parse the v3 `separator` independently of `prefix`'
assert_contains "$MIGRATE_COMMAND" 'source files, raw content, safelist entries, `@apply`, and plugin-generated'
assert_contains "$MIGRATE_COMMAND" "Rewrite each complete confirmed token to v4's \`:\` variant separator"
assert_contains "$MIGRATE_COMMAND" 'compare the generated selector and'
assert_contains "$MIGRATE_COMMAND" 'V4 `@config` does not support `separator`'
assert_contains "$MIGRATE_COMMAND" 'Every raw content entry has an exactly equivalent v4 inline source'
assert_contains "$MIGRATE_COMMAND" 'The v3 prefix import and every prefixed utility are migrated and verified losslessly'
assert_contains "$MIGRATE_COMMAND" 'Every custom-separator token is rewritten to v4 colon form with generated equivalence verified'
assert_contains "$MIGRATE_COMMAND" 'bind the complete set to `<CSS_ENTRIES>`'
assert_contains "$MIGRATE_COMMAND" 'Generate an equivalent converted configuration block for every independently'
assert_contains "$MIGRATE_COMMAND" 'Never omit converted configuration merely because an entry is secondary.'
assert_contains "$MIGRATE_COMMAND" 'Every independently built CSS entry contains equivalent converted configuration'
assert_contains "$MIGRATE_COMMAND" 'Bind the directory containing the selected v3 configuration and its application'
assert_contains "$MIGRATE_COMMAND" 'Bind that verified owner to `<PACKAGE_ROOT>`'
assert_contains "$MIGRATE_COMMAND" 'selector bound to `<WORKSPACE_MEMBER>`.'
assert_contains "$MIGRATE_COMMAND" 'Never run an unscoped dependency or'
assert_contains "$MIGRATE_COMMAND" 'the requested member manifest and owning lockfile receive dependency changes'
assert_contains "$MIGRATE_COMMAND" '`<WORKSPACE_MEMBER>` selector from `<PACKAGE_ROOT>` so the owning lockfile is'
assert_contains "$MIGRATE_COMMAND" '### Preset Chain Preservation'
assert_contains "$MIGRATE_COMMAND" 'replacements, `theme.extend`, `safelist`, `prefix`, `separator`, `corePlugins`,'
assert_contains "$MIGRATE_COMMAND" '`presets`, `darkMode`'
assert_contains "$MIGRATE_COMMAND" 'Recursively resolve a preset only when every link is a statically'
assert_contains "$MIGRATE_COMMAND" 'Do not partially migrate a preset chain.'
assert_contains "$MIGRATE_COMMAND" 'block migration completion and config removal.'
assert_contains "$MIGRATE_COMMAND" 'compare the fully resolved effective v3'
assert_contains "$MIGRATE_COMMAND" 'all referenced local preset files unchanged'
assert_contains "$MIGRATE_COMMAND" 'Every preset chain is fully resolved and migrated with equivalent generated behavior'
assert_contains "$MIGRATE_COMMAND" '### Core Plugin Preservation'
assert_contains "$MIGRATE_COMMAND" '`corePlugins: { preflight: false }`'
assert_contains "$MIGRATE_COMMAND" '@layer theme, base, components, utilities;'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss/theme.css" layer(theme);'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss/utilities.css" layer(utilities);'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss/theme.css" layer(theme) prefix(<PREFIX>);'
assert_contains "$MIGRATE_COMMAND" '@import "tailwindcss/utilities.css" layer(utilities) prefix(<PREFIX>) important;'
assert_contains "$MIGRATE_COMMAND" 'setting, and block migration completion and config removal. JavaScript'
assert_contains "$MIGRATE_COMMAND" '`@config` does not support `corePlugins` in v4'
assert_contains "$MIGRATE_COMMAND" 'contains no preflight import'
assert_contains "$MIGRATE_COMMAND" 'every other disabled core plugin remains unresolved with the config retained'
assert_not_matches "$MIGRATE_COMMAND" 'tailwindcss -i \./src/input\.css'
for integration in CLI PostCSS; do
  assert_contains "$MIGRATE_COMMAND" "### $integration Verification"
  assert_contains "$MIGRATE_COMMAND" "### $integration Migration Completion Criteria"
  assert_contains "$MIGRATE_COMMAND" "### $integration Migration Next Steps"
done
assert_contains "$MIGRATE_COMMAND" 'Use only the migration completion criteria for the selected integration.'

INIT_COMMAND="$PLUGIN_DIR/commands/init.md"
INIT_SKILL="$PLUGIN_DIR/skills/init/SKILL.md"
for integration in CLI Vite PostCSS; do
  assert_contains "$INIT_COMMAND" "### $integration Verification"
  assert_contains "$INIT_COMMAND" "### $integration Completion Criteria"
  assert_contains "$INIT_COMMAND" "### $integration Next Steps"
done
assert_contains "$INIT_COMMAND" 'Use only the completion criteria for the selected integration, together with'
assert_contains "$INIT_COMMAND" 'Bind the selected CSS entry path to `<CSS_ENTRY>`'
assert_contains "$INIT_COMMAND" 'derive a distinct sibling output path and bind it to `<CSS_OUTPUT>`'
assert_contains "$INIT_COMMAND" '"css": "tailwindcss -i <CSS_ENTRY> -o <CSS_OUTPUT> --minify"'
assert_contains "$INIT_COMMAND" '<PUBLIC_CSS_URL>'
assert_contains "$INIT_COMMAND" '## Initialization Operation Root'
assert_contains "$INIT_COMMAND" 'requested project path to `<INIT_TARGET>` as one concrete normalized'
assert_contains "$INIT_COMMAND" 'Treat `<INIT_TARGET>` as the application and integration mutation scope'
assert_contains "$INIT_COMMAND" 'Find the nearest ancestor'
assert_contains "$INIT_COMMAND" 'bind that ancestor to `<PACKAGE_ROOT>`'
assert_contains "$INIT_COMMAND" '`pnpm-workspace.yaml`. Confirm that the workspace configuration actually'
assert_contains "$INIT_COMMAND" 'includes `<INIT_TARGET>`, then bind that ancestor to `<PACKAGE_ROOT>`'
assert_contains "$INIT_COMMAND" 'explicit workspace/member selector bound to `<WORKSPACE_MEMBER>`'
assert_contains "$INIT_COMMAND" 'Never run an unscoped install or script command at the workspace root'
assert_contains "$INIT_COMMAND" 'member request. Verify that dependency changes affect only the requested'
assert_contains "$INIT_COMMAND" 'member manifest and the owning lockfile; do not modify unrelated packages.'
assert_contains "$INIT_COMMAND" 'Never create a lockfile in the member or at a different ancestor'
assert_contains "$INIT_COMMAND" 'Every application discovery, integration edit, and direct tool command used `<INIT_TARGET>`'
assert_contains "$INIT_COMMAND" 'Every workspace package-manager command explicitly targeted `<WORKSPACE_MEMBER>`'
assert_contains "$INIT_COMMAND" 'No file in the invocation directory changed unless it is `<INIT_TARGET>` or the verified owning package root'
assert_contains "$INIT_COMMAND" '## Step 5: Create or Merge CSS Entry File'
assert_contains "$INIT_COMMAND" 'Use this full template only for a new file.'
assert_contains "$INIT_COMMAND" 'Never overwrite an existing CSS entry'
assert_contains "$INIT_COMMAND" 'Preserve every existing import, rule, comment, at-rule, declaration, and'
assert_contains "$INIT_COMMAND" 'after any `@charset`'
assert_contains "$INIT_COMMAND" 'Treat incompatible Tailwind import modifiers'
assert_contains "$INIT_COMMAND" 'stop before writing the dependent change.'
assert_contains "$INIT_COMMAND" '### CSS Entry Preservation Criteria'
assert_contains "$INIT_COMMAND" 'An existing `<CSS_ENTRY>` was read completely and changed only by a verified in-place merge'
assert_contains "$INIT_SKILL" 'one normalized `<INIT_TARGET>`.'
assert_contains "$INIT_SKILL" 'every discovery, package-manager command, write, and validation.'
assert_not_matches "$INIT_COMMAND" 'tailwindcss -i \./css/input\.css'

for package_command in 'pnpm add -D' 'yarn add -D' 'bun add -d'; do
  assert_contains "$INIT_COMMAND" "$package_command"
  assert_contains "$MIGRATE_COMMAND" "$package_command"
done
for package_file in package-lock.json pnpm-lock.yaml yarn.lock bun.lock bun.lockb; do
  assert_contains "$INIT_COMMAND" "$package_file"
  assert_contains "$MIGRATE_COMMAND" "$package_file"
done
for package_workflow in "$INIT_COMMAND" "$MIGRATE_COMMAND"; do
  assert_contains "$package_workflow" '## Package Manager Selection'
  assert_contains "$package_workflow" 'Do not create a lockfile for a different package manager.'
  assert_not_matches "$package_workflow" 'npx[[:space:]]+@tailwindcss/cli'
done

OPTIMIZE_COMMAND="$PLUGIN_DIR/commands/optimize.md"
assert_contains "$OPTIMIZE_COMMAND" '### Local CLI Measurement'
assert_contains "$OPTIMIZE_COMMAND" 'node_modules/@tailwindcss/cli/package.json'
assert_contains "$OPTIMIZE_COMMAND" 'node "<LOCAL_CLI_ENTRY>"'
assert_contains "$OPTIMIZE_COMMAND" 'Verify that the resolved entry remains inside'
assert_contains "$OPTIMIZE_COMMAND" '### Existing Generated CSS Measurement'
assert_contains "$OPTIMIZE_COMMAND" 'Do not install `@tailwindcss/cli` solely for measurement.'
assert_contains "$OPTIMIZE_COMMAND" 'record the measurement limitation and continue'
assert_not_matches "$OPTIMIZE_COMMAND" 'npx[[:space:]]'
assert_contains "$OPTIMIZE_COMMAND" 'Bind the selected Tailwind CSS entry to `<CSS_ENTRY>`'
assert_contains "$OPTIMIZE_COMMAND" 'Bind the requested or implicitly derived path to `<OPTIMIZE_TARGET>`'
assert_contains "$OPTIMIZE_COMMAND" 'Retain the complete `<TEMPLATE_FILES>` set'
assert_contains "$OPTIMIZE_COMMAND" '"<OPTIMIZE_TARGET>"'
assert_contains "$OPTIMIZE_COMMAND" '"<TEMPLATE_FILES>"'
assert_contains "$OPTIMIZE_COMMAND" 'Apply changes only to `<CSS_ENTRY>` and the selected integration associated'
assert_contains "$OPTIMIZE_COMMAND" 'grep '\''@source'\'' "<CSS_ENTRY>"'
assert_contains "$OPTIMIZE_COMMAND" '"<GENERATED_CSS>"'
assert_not_matches "$OPTIMIZE_COMMAND" '-i[[:space:]]+input\.css'
assert_not_matches "$OPTIMIZE_COMMAND" '/tmp/'
assert_not_matches "$OPTIMIZE_COMMAND" 'class="\[\^"\]\*".*[[:space:]]\.[[:space:]]+2>/dev/null'
assert_contains "$OPTIMIZE_COMMAND" "Bind \`<SUPPORTED_SOURCE_EXTENSIONS>\` once to the project's complete source set"
for source_extension in js jsx ts tsx html htm templ vue svelte astro php blade.php erb hbs md mdx ejs twig liquid njk nunjucks pug jade haml slim razor cshtml; do
  assert_contains "$OPTIMIZE_COMMAND" "$source_extension"
done
assert_contains "$OPTIMIZE_COMMAND" 'This baseline is not an allowlist.'
assert_contains "$OPTIMIZE_COMMAND" 'every other text source selected by an `@source` rule or the'
assert_contains "$OPTIMIZE_COMMAND" 'Never omit a target-associated source merely because its extension is absent'
assert_contains "$OPTIMIZE_COMMAND" 'rather than rediscovering files. Recognize both'
assert_contains "$OPTIMIZE_COMMAND" '`class` and `className` values in these forms:'
assert_contains "$OPTIMIZE_COMMAND" 'double-quoted literals:'
assert_contains "$OPTIMIZE_COMMAND" 'single-quoted literals:'
assert_contains "$OPTIMIZE_COMMAND" 'interpolation-free backtick literals'
assert_contains "$OPTIMIZE_COMMAND" 'literal containing `${...}` as a dynamic class expression'
assert_contains "$OPTIMIZE_COMMAND" 'not "unused"'
assert_contains "$OPTIMIZE_COMMAND" 'Dynamic class expressions requiring review'
assert_contains "$OPTIMIZE_COMMAND" 'standards-compliant CSS selector parser or a read-only equivalent'
assert_contains "$OPTIMIZE_COMMAND" 'CSS-unescape'
assert_contains "$OPTIMIZE_COMMAND" '`hover:bg-red-500`, `w-1/2`, arbitrary values like `bg-[#123456]`'
assert_contains "$OPTIMIZE_COMMAND" '`hover:bg-red-500`, `w-1/2`, arbitrary values like `bg-[#123456]`, important'
assert_contains "$OPTIMIZE_COMMAND" 'forms like `font-bold!`, and negative forms like `-mt-4`.'
assert_contains "$OPTIMIZE_COMMAND" 'Do not use a grep'
assert_contains "$OPTIMIZE_COMMAND" 'report generated class count and CSS-only comparison as'
assert_contains "$OPTIMIZE_COMMAND" 'unavailable. Continue with source coverage'
assert_not_matches "$OPTIMIZE_COMMAND" "grep -oE '\\\\.[a-zA-Z]"
assert_not_matches "$OPTIMIZE_COMMAND" 'head -50'

OPTIMIZE_SKILL="$PLUGIN_DIR/skills/optimize/SKILL.md"
assert_contains "$OPTIMIZE_SKILL" 'argument-hint: "[path] [--report|--fix|--verbose]"'

AUDIT_COMMAND="$PLUGIN_DIR/commands/audit.md"
assert_contains "$AUDIT_COMMAND" '## v3 Migration Guard'
assert_contains "$AUDIT_COMMAND" 'When `--fix` is present and a v3 project is detected'
assert_contains "$AUDIT_COMMAND" 'Do not replace `@tailwind` directives'
assert_contains "$AUDIT_COMMAND" 'Keep every v3 compliance finding read-only'
assert_contains "$AUDIT_COMMAND" '`$tailwind:migrate`'
assert_contains "$AUDIT_COMMAND" 'Bind the requested path to `<AUDIT_TARGET>`'
assert_contains "$AUDIT_COMMAND" 'complete retained `<AUDIT_SOURCE_FILES>`'
assert_contains "$AUDIT_COMMAND" '"<AUDIT_TARGET>"'
assert_contains "$AUDIT_COMMAND" 'Parse `--focus` into `<AUDIT_FOCUS>` using this allowlist'
assert_contains "$AUDIT_COMMAND" '`<AUDIT_FOCUS>` to `all` and bind all four categories.'
assert_contains "$AUDIT_COMMAND" 'report sections, auto-fixes, counts, and completion criteria must operate only'
assert_contains "$AUDIT_COMMAND" 'Include only rows and findings for `<AUDIT_CATEGORIES>`.'
assert_contains "$AUDIT_COMMAND" 'Apply only fixes belonging to `<AUDIT_CATEGORIES>`'
assert_contains "$AUDIT_COMMAND" 'Class token order does not determine the effective winner'
assert_contains "$AUDIT_COMMAND" 'Do not auto-fix conflicting'
assert_contains "$AUDIT_COMMAND" '## Step 1: Discover Project Sources'
assert_contains "$AUDIT_COMMAND" 'fd -e js -e jsx -e ts -e tsx'
assert_contains "$AUDIT_COMMAND" 'baseline, not an allowlist.'
assert_contains "$AUDIT_COMMAND" 'add every target-scoped text source selected by the active'
assert_contains "$AUDIT_COMMAND" 'Bind the resulting complete plain-text set once to `<AUDIT_SOURCE_FILES>`'
assert_contains "$AUDIT_COMMAND" 'merely because its extension is absent from the baseline. Reuse these exact'
assert_contains "$AUDIT_COMMAND" 'bindings for category checks, report counts, auto-fixes, and completion'
assert_contains "$AUDIT_COMMAND" 'Analyze the complete `<AUDIT_SOURCE_FILES>` binding'
assert_contains "$AUDIT_COMMAND" '**Files scanned:** X Tailwind plain-text sources, Y CSS files'
assert_contains "$AUDIT_COMMAND" 'Limit every change to the retained `<AUDIT_SOURCE_FILES>` and'
assert_not_matches "$AUDIT_COMMAND" '--include="\*\.html".*--include="\*\.templ".*--include="\*\.jsx"'
assert_not_matches "$AUDIT_COMMAND" 'head -100'
assert_not_matches "$AUDIT_COMMAND" 'head -20'

AUDIT_SKILL="$PLUGIN_DIR/skills/audit/SKILL.md"
assert_contains "$AUDIT_SKILL" '`--focus` is allowlisted to `consistency`, `performance`, `practices`, or `v4`.'
assert_contains "$AUDIT_SKILL" 'limits discovery, reporting, fixes, counts, and completion checks'

printf 'Tailwind Codex workflow skill tests passed.\n'
