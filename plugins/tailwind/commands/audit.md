---
argument-hint: "[path] [--fix]"
description: "Audit Tailwind CSS usage for best practices and consistency"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(fd:*)", "Bash(grep:*)", "Bash(ls:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_utilities", "mcp__tailwindcss__convert_css_to_tailwind"]
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

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-audit" "COMPLETE"; fi`

## Step 1: Discover Template Files

```bash
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -e astro -e php -e blade.php -e erb -e hbs -d 5 2>/dev/null | head -100
fd -e css -d 5 2>/dev/null | head -20
```

## Step 2: Audit Categories

### Category 1: Consistency

Mixed spacing units (`p-4` alongside `padding: 16px`); arbitrary values where theme would work (`w-[200px]` vs `w-52`); mixed `gap-4` and `space-x-4` in same component.

| Issue | Example | Fix |
|-------|---------|-----|
| Duplicate spacing | `p-4 p-6` | Remove `p-4` |
| Conflicting display | `flex block` | Choose one |
| Redundant color | `bg-blue-500 bg-red-500` | Remove one |
| Overridden responsive | `md:flex md:block` | Remove one |

Inconsistent color usage: hardcoded hex (`bg-[#3b82f6]`) when theme color exists (`bg-primary`); mixing `blue-400`/`500`/`600` randomly.

### Category 2: Performance

Inline styles that should be utilities:

| Inline | Tailwind |
|--------|----------|
| `style="display: flex"` | `flex` |
| `style="margin: 1rem"` | `m-4` |
| `style="padding: 0.5rem 1rem"` | `py-2 px-4` |
| `style="font-weight: bold"` | `font-bold` |
| `style="text-align: center"` | `text-center` |

Use `mcp__tailwindcss__convert_css_to_tailwind` for complex conversions.

**Large arbitrary values:** more than ~10 `[...]` arbitrary values per file suggests missing theme configuration. Repeated arbitrary values should be added to `@theme`.

### Category 3: Best Practices

**Class ordering** (recommended): `layout → spacing → sizing → typography → colors → effects → interactive`.

```text
Good: "flex items-center gap-4 p-4 w-full text-sm text-gray-700 bg-white shadow-sm hover:bg-gray-50 transition-colors"
Bad:  "hover:bg-gray-50 flex bg-white p-4 text-sm shadow-sm w-full gap-4 items-center text-gray-700 transition-colors"
```

**Component extraction** — find class combinations that appear 3+ times:

```bash
grep -ohr 'class="[^"]*"' --include="*.html" --include="*.templ" --include="*.jsx" | sort | uniq -c | sort -rn | head -20
```

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
| `darkMode: 'class'` | `@variant dark { }` |

```bash
ls tailwind.config.* 2>/dev/null               # if found, recommend /tailwind-migrate
grep -l '@import.*tailwindcss' *.css */*.css 2>/dev/null   # should find one
grep -l '@tailwind' *.css */*.css 2>/dev/null              # should be empty
```

## Step 3: Generate Report

```
## Tailwind CSS Audit Report

**Project:** [path]
**Files scanned:** X templates, Y CSS files

### Summary

| Category | Issues | Auto-fixable |
|----------|--------|--------------|
| Consistency | X | Y |
| Performance | X | Y |
| Best Practices | X | Y |
| v4 Compliance | X | Y |
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

## Step 4: Auto-Fix (if `--fix`)

Auto-apply: remove duplicate utilities (keep last), convert inline styles, reorder classes to convention, update v3 → v4 syntax in CSS files only.

**Do NOT auto-fix:** component extraction (naming requires user input); color choices (subjective); arbitrary values (may be intentional).

```
## Auto-Fix Results

Fixed X issues automatically:
- Removed Y duplicate utilities
- Converted Z inline styles
- Reordered W class strings
- Updated V v3 patterns to v4

Remaining issues: X (require manual review)
```

## Notes

- Use `mcp__tailwindcss__search_tailwind_docs` to verify utility suggestions
- Use `mcp__tailwindcss__get_tailwind_utilities` to find equivalent utilities
- Always review auto-fixes before committing
- Run audit after major changes to catch regressions

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. All template files scanned
2. Audit report generated
3. If `--fix` provided: auto-fixes applied
4. Summary displayed

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
