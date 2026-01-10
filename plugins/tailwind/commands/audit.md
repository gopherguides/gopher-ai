---
argument-hint: "[path] [--fix]"
description: "Audit Tailwind CSS usage for best practices and consistency"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_utilities", "mcp__tailwindcss__convert_css_to_tailwind"]
---

# Audit Tailwind CSS Usage

**If `$ARGUMENTS` is empty or not provided:**

Audit Tailwind CSS usage in the current project for best practices, consistency, and optimization opportunities.

**Usage:** `/tailwind-audit [path] [options]`

**Examples:**

- `/tailwind-audit` - Audit entire project
- `/tailwind-audit ./src` - Audit specific directory
- `/tailwind-audit --fix` - Audit and auto-fix issues where possible

**What this command checks:**

1. **Consistency** - Mixed units, duplicate utilities, conflicting breakpoints
2. **Performance** - Inline styles, missing utilities, CSS bloat
3. **Best Practices** - Component extraction, class ordering, accessibility
4. **v4 Compliance** - @theme usage, deprecated patterns, migration issues

Proceed with auditing the current project.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- **Path**: Directory or file to audit (default: current directory)
- **--fix**: Auto-fix issues where possible
- **--report**: Generate detailed markdown report
- **--focus=<area>**: Focus on specific area (consistency, performance, practices, v4)

## Loop Initialization

Initialize persistent loop to ensure audit completes fully:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-audit" "COMPLETE"`

## Step 1: Discover Template Files

Find all files that may contain Tailwind classes:

```bash
# Find template files
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -e astro -e php -e blade.php -e erb -e hbs -d 5 2>/dev/null | head -100

# Find CSS files
fd -e css -d 5 2>/dev/null | head -20
```

## Step 2: Audit Categories

### Category 1: Consistency Issues

**Check for mixed spacing units:**

```bash
# Find mixed px values in Tailwind context
grep -r "class=" --include="*.html" --include="*.templ" --include="*.jsx" --include="*.tsx" | grep -E "p-\d|m-\d" | head -20
```

Look for patterns like:
- `p-4` alongside `padding: 16px` (should use only Tailwind)
- `w-[200px]` when `w-52` (208px) would work
- Mixed `gap-4` and `space-x-4` in same component

**Check for duplicate/conflicting utilities:**

| Issue | Example | Fix |
|-------|---------|-----|
| Duplicate spacing | `p-4 p-6` | Remove `p-4` |
| Conflicting display | `flex block` | Choose one |
| Redundant color | `bg-blue-500 bg-red-500` | Remove one |
| Overridden responsive | `md:flex md:block` | Remove one |

**Check for inconsistent color usage:**

Look for:
- Hardcoded hex colors when theme colors exist: `bg-[#3b82f6]` vs `bg-primary`
- Inconsistent shade usage: mixing `blue-400`, `blue-500`, `blue-600` randomly

### Category 2: Performance Issues

**Inline styles that should be utilities:**

```bash
# Find inline styles
grep -r "style=" --include="*.html" --include="*.templ" --include="*.jsx" --include="*.tsx" | head -20
```

Common conversions:
| Inline Style | Tailwind Utility |
|--------------|------------------|
| `style="display: flex"` | `flex` |
| `style="margin: 1rem"` | `m-4` |
| `style="padding: 0.5rem 1rem"` | `py-2 px-4` |
| `style="font-weight: bold"` | `font-bold` |
| `style="text-align: center"` | `text-center` |

Use `mcp__tailwindcss__convert_css_to_tailwind` for complex conversions.

**Large arbitrary values:**

Look for excessive use of arbitrary values `[...]`:
- More than 10 arbitrary values suggests missing theme configuration
- Repeated arbitrary values should be added to `@theme`

### Category 3: Best Practices

**Class ordering convention:**

Recommended order: `layout → spacing → sizing → typography → colors → effects → interactive`

```text
Good: "flex items-center gap-4 p-4 w-full text-sm text-gray-700 bg-white shadow-sm hover:bg-gray-50 transition-colors"
Bad:  "hover:bg-gray-50 flex bg-white p-4 text-sm shadow-sm w-full gap-4 items-center text-gray-700 transition-colors"
```

**Component extraction candidates:**

Find class combinations that appear 3+ times:

```bash
# Extract class strings and count duplicates
grep -ohr 'class="[^"]*"' --include="*.html" --include="*.templ" --include="*.jsx" | sort | uniq -c | sort -rn | head -20
```

Repeated patterns should be extracted:

```css
@layer components {
  .btn {
    @apply px-4 py-2 rounded-lg font-medium transition-colors;
  }
  .card {
    @apply p-6 bg-card rounded-xl border border-border shadow-sm;
  }
}
```

**Accessibility issues:**

| Check | Issue | Fix |
|-------|-------|-----|
| Focus indicators | Missing `focus:` or `focus-visible:` | Add `focus-visible:ring-2 focus-visible:ring-primary` |
| Screen reader | Hidden content without `sr-only` | Add `sr-only` for visually hidden text |
| Color contrast | Low contrast combinations | Use higher contrast colors |
| Interactive elements | Missing hover/focus states | Add `hover:` and `focus:` variants |

### Category 4: Tailwind v4 Compliance

**Deprecated v3 patterns:**

| v3 Pattern | v4 Replacement |
|------------|----------------|
| `@tailwind base;` | `@import "tailwindcss";` |
| `@tailwind components;` | (included in import) |
| `@tailwind utilities;` | (included in import) |
| `tailwind.config.js` | `@theme { }` in CSS |
| `theme.extend.colors` | `--color-*` in @theme |
| `darkMode: 'class'` | `@variant dark { }` |

**Check for v3 config file:**

```bash
ls tailwind.config.* 2>/dev/null
```

If found, recommend using `/tailwind-migrate` command.

**Check CSS file for v4 syntax:**

```bash
# Should find @import "tailwindcss"
grep -l '@import.*tailwindcss' *.css */*.css 2>/dev/null

# Should NOT find old directives
grep -l '@tailwind' *.css */*.css 2>/dev/null
```

## Step 3: Generate Report

```text
## Tailwind CSS Audit Report

**Project:** [path]
**Files scanned:** X template files, Y CSS files
**Date:** [current date]

### Summary

| Category | Issues | Auto-fixable |
|----------|--------|--------------|
| Consistency | X | Y |
| Performance | X | Y |
| Best Practices | X | Y |
| v4 Compliance | X | Y |
| **Total** | **X** | **Y** |

### Critical Issues

[List issues that should be fixed immediately]

### Consistency Issues

| File | Line | Issue | Suggestion |
|------|------|-------|------------|
| ... | ... | ... | ... |

### Performance Issues

| File | Line | Issue | Suggestion |
|------|------|-------|------------|
| ... | ... | ... | ... |

### Best Practices

| File | Line | Issue | Suggestion |
|------|------|-------|------------|
| ... | ... | ... | ... |

### Component Extraction Candidates

These class combinations appear 3+ times and could be extracted:

| Pattern | Count | Suggested Name |
|---------|-------|----------------|
| `flex items-center gap-4` | 12 | `.flex-row` |
| `text-sm text-muted-foreground` | 8 | `.text-muted` |
| `px-4 py-2 rounded-lg` | 6 | `.btn-base` |

### v4 Migration Needed

[List any v3 patterns that need migration]

### Recommendations

1. [Prioritized list of improvements]
2. ...
3. ...
```

## Step 4: Auto-Fix (if --fix provided)

When `--fix` flag is present, automatically fix:

1. **Remove duplicate utilities** - Keep the last one
2. **Convert inline styles** - Replace with Tailwind utilities
3. **Fix class ordering** - Reorder to convention
4. **Update v3 to v4 syntax** - In CSS files only

**Do NOT auto-fix:**
- Component extraction (requires user decision on naming)
- Color choices (subjective)
- Arbitrary values (may be intentional)

After fixes:

```text
## Auto-Fix Results

Fixed X issues automatically:
- Removed Y duplicate utilities
- Converted Z inline styles
- Reordered W class strings
- Updated V v3 patterns to v4

Remaining issues: X (require manual review)

Files modified:
- path/to/file1.html (3 fixes)
- path/to/file2.templ (2 fixes)
```

## Notes

- Use `mcp__tailwindcss__search_tailwind_docs` to verify utility suggestions
- Use `mcp__tailwindcss__get_tailwind_utilities` to find equivalent utilities
- Always review auto-fixes before committing
- Run audit after major changes to catch regressions

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All template files have been scanned
2. Audit report has been generated
3. If `--fix` flag provided: auto-fixes have been applied
4. Summary of findings has been displayed

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the audit may be incomplete.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
