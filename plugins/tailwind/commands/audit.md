---
argument-hint: "[path] [--fix]"
description: "Audit Tailwind CSS usage for best practices and consistency"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(fd:*)", "Bash(grep:*)", "Bash(ls:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Audit Tailwind CSS Usage

**If `$ARGUMENTS` is empty or not provided:**

Audit Tailwind CSS usage for best practices, consistency, and optimization opportunities.

**Usage:** `/tailwind-audit [path] [options]`

- `/tailwind-audit` — audit entire project
- `/tailwind-audit ./src` — audit specific directory
- `/tailwind-audit --fix` — audit and auto-fix where possible

**Checks:** consistency (mixed units, duplicate utilities, conflicting breakpoints) · performance (inline styles, missing utilities, CSS bloat) · best practices (component extraction, class ordering, accessibility) · v4 compliance (`@theme` usage, deprecated patterns).

Proceed with auditing the current project.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- **Path** — directory or file (default: current directory)
- `--fix` — auto-fix issues where possible
- `--report` — generate detailed markdown report
- `--focus=<area>` — focus on specific area (consistency / performance / practices / v4)

Bind the requested path to `<AUDIT_TARGET>` as a concrete normalized path. If
no path was provided, bind the current directory. Resolve the containing
project root to `<PROJECT_ROOT>` for configuration checks. If the target is a
file, analyze that file directly; if it is a directory, discover every
supported file beneath it. Stop with a clear error when the target does not
exist.

Parse `--focus` into `<AUDIT_FOCUS>` using this allowlist, then bind its
selected categories to `<AUDIT_CATEGORIES>`:

| Focus value | Selected category |
|-------------|-------------------|
| `consistency` | Consistency |
| `performance` | Performance |
| `practices` | Best Practices |
| `v4` | Tailwind v4 Compliance |

Reject any other focus value with a clear error. Without `--focus`, bind
`<AUDIT_FOCUS>` to `all` and bind all four categories. Discovery, checks,
report sections, auto-fixes, counts, and completion criteria must operate only
on `<AUDIT_CATEGORIES>`; do not inspect, report, or modify an unselected
category.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-audit" "COMPLETE"; fi`

## Step 1: Discover Project Sources

```bash
fd -e js -e jsx -e ts -e tsx -e html -e htm -e templ -e vue -e svelte -e astro -e php -e erb -e hbs -e md -e mdx -e ejs -e twig -e liquid -e njk -e nunjucks -e pug -e jade -e haml -e slim -e razor -e cshtml "<AUDIT_TARGET>" 2>/dev/null
fd -e css "<AUDIT_TARGET>" 2>/dev/null
```

Use the same project-complete Tailwind source model as optimize. The command
above is a baseline, not an allowlist. Tailwind scans non-ignored plain-text
project sources, so add every target-scoped text source selected by the active
build integration or an `@source` rule. Exclude CSS, binaries, lockfiles,
`node_modules`, and ignored paths according to Tailwind's detection rules.

Bind the resulting complete plain-text set once to `<AUDIT_SOURCE_FILES>` and
the complete CSS set to `<AUDIT_CSS_FILES>`. The source set must include plain
JavaScript and TypeScript and must never omit an integration-associated source
merely because its extension is absent from the baseline. Reuse these exact
bindings for category checks, report counts, auto-fixes, and completion; do not
rediscover a narrower set later.

Run only the discovery needed by the selected categories:

- Consistency and Performance: use `<AUDIT_SOURCE_FILES>` and `<AUDIT_CSS_FILES>`.
- Best Practices: use `<AUDIT_SOURCE_FILES>`; inspect `<AUDIT_CSS_FILES>` only when needed
  to report an existing extraction target.
- Tailwind v4 Compliance: use `<AUDIT_CSS_FILES>` plus the project-level package,
  Tailwind, PostCSS, and build configuration needed for version detection.

Derive each selected category's file set only from the retained complete
bindings. Do not truncate discovery output. When
`<AUDIT_TARGET>` is a file, use it as the complete set for a selected category
when it is a Tailwind-scanned plain-text source or relevant CSS. Report zero
applicable files instead of widening discovery beyond the target.

## Step 2: Audit Categories

### Category 1: Consistency

Mixed spacing units (`p-4` alongside `padding: 16px`); arbitrary values where theme would work (`w-[200px]` vs `w-52`); mixed `gap-4` and `space-x-4` in same component.

| Issue | Example | Fix |
|-------|---------|-----|
| Exact duplicate | `p-4 p-4` | Remove the repeated token |
| Conflicting spacing | `p-4 p-6` | Review the intended value |
| Conflicting display | `flex block` | Review the intended display |
| Conflicting color | `bg-blue-500 bg-red-500` | Review the intended color |
| Conflicting responsive | `md:flex md:block` | Review the intended display |

Inconsistent color usage: hardcoded hex (`bg-[#3b82f6]`) when theme color exists (`bg-primary`); mixing `blue-400`/`500`/`600` randomly.

Class token order does not determine the effective winner for conflicting
utilities; Tailwind's generated stylesheet order controls equal-specificity
rules. Never infer the intended or effective winner from which class appears
last in HTML. Report conflicting utilities for manual review unless the
project's generated stylesheet and active variants establish the effective
winner and the user's intent independently. Do not auto-fix conflicting
utilities when either fact is ambiguous.

### Category 2: Performance

Inline styles that should be utilities:

| Inline | Tailwind |
|--------|----------|
| `style="display: flex"` | `flex` |
| `style="margin: 1rem"` | `m-4` |
| `style="padding: 0.5rem 1rem"` | `py-2 px-4` |
| `style="font-weight: bold"` | `font-bold` |
| `style="text-align: center"` | `text-center` |

Use bundled Tailwind references and official documentation for complex conversions.

**Large arbitrary values:** more than ~10 `[...]` arbitrary values per file suggests missing theme configuration. Repeated arbitrary values should be added to `@theme`.

### Category 3: Best Practices

**Class ordering** (recommended): `layout → spacing → sizing → typography → colors → effects → interactive`.

```text
Good: "flex items-center gap-4 p-4 w-full text-sm text-gray-700 bg-white shadow-sm hover:bg-gray-50 transition-colors"
Bad:  "hover:bg-gray-50 flex bg-white p-4 text-sm shadow-sm w-full gap-4 items-center text-gray-700 transition-colors"
```

**Component extraction** — find class combinations that appear 3+ times:

Analyze the complete `<AUDIT_SOURCE_FILES>` binding for repeated static class
combinations. Do not fall back to an HTML/Templ/JSX-only grep or rediscover a
smaller extension set.

Repeated patterns become `@layer components` rules:

```css
@layer components {
  .btn { @apply px-4 py-2 rounded-lg font-medium transition-colors; }
  .card { @apply p-6 bg-card rounded-xl border border-border shadow-sm; }
}
```

**Accessibility:**

| Check | Issue | Fix |
|-------|-------|-----|
| Focus indicators | Missing `focus:` / `focus-visible:` | Add `focus-visible:ring-2 focus-visible:ring-primary` |
| Screen reader | Hidden content without `sr-only` | Add `sr-only` |
| Color contrast | Low contrast | Use higher contrast colors |
| Interactive elements | Missing hover/focus states | Add `hover:`/`focus:` variants |

### Category 4: Tailwind v4 Compliance

| v3 | v4 |
|----|-----|
| `@tailwind base/components/utilities` | `@import "tailwindcss";` |
| `tailwind.config.js` | `@theme { }` in CSS |
| `theme.extend.colors` | `--color-*` in `@theme` |
| `darkMode: 'class'` | `@custom-variant dark (...)` plus `.dark { }` overrides |

```bash
ls "<PROJECT_ROOT>"/tailwind.config.* 2>/dev/null
grep -rl '@import.*tailwindcss' --include="*.css" "<AUDIT_TARGET>" 2>/dev/null
grep -rl '@tailwind' --include="*.css" "<AUDIT_TARGET>" 2>/dev/null
```

## v3 Migration Guard

Apply this guard only when Tailwind v4 Compliance is in
`<AUDIT_CATEGORIES>`. Treat a project as v3 when the installed Tailwind major version is v3 or its
CSS still uses v3 `@tailwind` directives. A JavaScript configuration alone is
only a review signal because v4 can load one explicitly with `@config`. When `--fix` is present and a v3 project is detected, apply this guard. Keep every v3 compliance finding read-only. Do not replace `@tailwind` directives, remove the JavaScript configuration, or alter Tailwind/PostCSS dependencies as an audit auto-fix.

Report that a complete migration is required and direct the user to the
explicit `$tailwind:migrate` workflow. Delegate to that workflow only when the
user separately requests migration; never apply a CSS-only subset from audit.
Version-independent fixes such as duplicate-utility removal may continue when
they do not alter migration state.

## Step 3: Generate Report

```
## Tailwind CSS Audit Report

**Project:** [project root]
**Audit target:** [concrete target]
**Files scanned:** X Tailwind plain-text sources, Y CSS files

### Summary

| Category | Issues | Auto-fixable |
|----------|--------|--------------|
| [Each selected category only] | X | Y |
| **Total** | **X** | **Y** |

### Findings (per category)

| File | Line | Issue | Suggestion |
|------|------|-------|------------|

### Component Extraction Candidates

| Pattern | Count | Suggested Name |
|---------|-------|----------------|
| `flex items-center gap-4` | 12 | `.flex-row` |
| `text-sm text-muted-foreground` | 8 | `.text-muted` |
| `px-4 py-2 rounded-lg` | 6 | `.btn-base` |

### v4 Migration Needed

[Any v3 patterns that need migration]
```

Include only rows and findings for `<AUDIT_CATEGORIES>`. Include Component
Extraction Candidates only when Best Practices is selected. Include v4
Migration Needed only when Tailwind v4 Compliance is selected. Counts and
totals must exclude unselected categories.

## Step 4: Auto-Fix (if `--fix`)

Apply only fixes belonging to `<AUDIT_CATEGORIES>`:

- Consistency: remove repeated occurrences of the exact same utility token,
  retaining one identical token. Do not choose between conflicting utilities.
- Performance: convert only unambiguous inline styles to equivalent utilities.
- Best Practices: reorder class strings to the documented convention.
- Tailwind v4 Compliance: on confirmed v4 projects, apply only v4-to-v4 syntax
  corrections that do not require dependency or configuration changes.

Limit every change to the retained `<AUDIT_SOURCE_FILES>` and
`<AUDIT_CSS_FILES>` applicable to the selected category. Never mutate a file
outside those target-scoped bindings.

**Do NOT auto-fix:** conflicting utilities based on HTML token order;
component extraction (naming requires user input); color choices (subjective);
arbitrary values (may be intentional).

```
## Auto-Fix Results

Fixed X issues automatically:
- Removed Y duplicate utilities
- Converted Z inline styles
- Reordered W class strings
- Reported V migration findings without partial v3 changes

Remaining issues: X (require manual review)
```

## Notes

- Use bundled Tailwind references and official documentation to verify utility suggestions and equivalents
- Always review auto-fixes before committing
- Run audit after major changes to catch regressions

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Every file in the complete retained `<AUDIT_SOURCE_FILES>` and applicable `<AUDIT_CSS_FILES>` bindings was scanned
2. Only the selected categories were inspected and included in the audit report
3. If `--fix` provided: only selected-category fixes were applied, ambiguous conflicts remain for manual review, and selected v3 migration findings remain unchanged
4. A summary containing only selected-category counts is displayed

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
