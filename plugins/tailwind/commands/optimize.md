---
argument-hint: "[--report|--fix]"
description: "Analyze and optimize Tailwind CSS output"
model: claude-sonnet-4-20250514
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_utilities"]
---

# Optimize Tailwind CSS

**If `$ARGUMENTS` is empty or not provided:**

Analyze Tailwind CSS output and provide optimization recommendations.

**Usage:** `/tailwind-optimize [options]`

**Examples:**

- `/tailwind-optimize` - Quick analysis
- `/tailwind-optimize --report` - Generate detailed report
- `/tailwind-optimize --fix` - Apply optimizations

**What this command analyzes:**

1. **Bundle size** - Measure CSS output size (dev vs prod)
2. **Source coverage** - Verify `@source` paths cover all templates
3. **Unused classes** - Find classes in CSS not used in templates
4. **CSS variable bloat** - Identify unused theme variables
5. **Build performance** - Check build times and suggest improvements

Proceed with optimization analysis.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- **--report**: Generate detailed markdown report
- **--fix**: Apply safe optimizations automatically
- **--verbose**: Show all findings, not just issues

## Step 1: Find CSS Files

Locate Tailwind CSS files:

```bash
# Find input CSS (with @import "tailwindcss")
grep -rl '@import.*tailwindcss' --include="*.css" . 2>/dev/null

# Find output CSS
ls **/output.css dist/**/*.css build/**/*.css public/**/*.css 2>/dev/null
```

## Step 2: Measure Bundle Size

### Development Build

```bash
# Build without minification
npx @tailwindcss/cli -i input.css -o /tmp/dev-output.css 2>&1

# Measure size
wc -c /tmp/dev-output.css
```

### Production Build

```bash
# Build with minification
npx @tailwindcss/cli -i input.css -o /tmp/prod-output.css --minify 2>&1

# Measure size
wc -c /tmp/prod-output.css

# Gzip size estimate
gzip -c /tmp/prod-output.css | wc -c
```

### Size Benchmarks

| Size Category | Range | Assessment |
|---------------|-------|------------|
| Excellent | < 10KB gzipped | Highly optimized |
| Good | 10-25KB gzipped | Normal for most apps |
| Acceptable | 25-50KB gzipped | Consider optimization |
| Large | > 50KB gzipped | Needs optimization |

Most Tailwind projects should ship < 10KB CSS gzipped.

## Step 3: Analyze Source Coverage

### Find Template Files

```bash
# Count template files
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -d 5 2>/dev/null | wc -l

# Show file types
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -d 5 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

### Check @source Configuration

Read the CSS input file and extract `@source` directives:

```bash
grep '@source' input.css
```

### Verify Coverage

For each `@source` pattern, verify files are found:

```bash
# Example: @source "./src/**/*.{js,jsx}"
fd -e js -e jsx ./src 2>/dev/null | wc -l
```

**Coverage issues to check:**

| Issue | Symptom | Fix |
|-------|---------|-----|
| Missing source | Classes not generated | Add `@source` for directory |
| Overly broad | Too much CSS generated | Use specific globs |
| Wrong path | Classes missing | Verify path exists |

## Step 4: Find Unused Classes

### Extract Used Classes

```bash
# Extract class names from templates
grep -ohr 'class="[^"]*"' --include="*.html" --include="*.templ" --include="*.jsx" --include="*.tsx" . 2>/dev/null | \
  sed 's/class="//g' | sed 's/"//g' | tr ' ' '\n' | sort -u > /tmp/used-classes.txt

wc -l /tmp/used-classes.txt
```

### Compare With Generated CSS

```bash
# Extract class names from CSS
grep -oE '\.[a-zA-Z][a-zA-Z0-9_-]*' output.css | sed 's/\.//' | sort -u > /tmp/css-classes.txt

# Find classes in CSS but not in templates
comm -23 /tmp/css-classes.txt /tmp/used-classes.txt | head -50
```

**Note:** Some "unused" classes may be:
- Dynamically generated (e.g., `bg-${color}-500`)
- Used by JavaScript
- From third-party libraries
- Base/reset styles (intentionally included)

## Step 5: CSS Variable Analysis

Tailwind v4 generates many CSS variables. Check for bloat:

```bash
# Count CSS variables in output
grep -c -- '--' output.css

# List unused color variables
grep -oE '--color-[a-z]+-[0-9]+' output.css | sort -u | wc -l
```

### Variable Categories

| Category | Expected | If Higher |
|----------|----------|-----------|
| Color vars | 50-100 | Using full palette when subset would work |
| Spacing vars | 20-30 | Normal |
| Font vars | 5-10 | Normal |
| Animation vars | 10-20 | Normal |

### Reducing Variable Bloat

If too many unused variables, consider:

1. **Define only needed colors in @theme:**

```css
@theme {
  /* Only define colors you actually use */
  --color-primary: oklch(0.6 0.2 250);
  --color-secondary: oklch(0.5 0.02 250);
  /* Don't rely on full Tailwind palette */
}
```

2. **Use specific source paths** to generate only needed utilities

## Step 6: Build Performance

### Measure Build Time

```bash
# Time a production build
time npx @tailwindcss/cli -i input.css -o output.css --minify 2>&1
```

### Performance Benchmarks

| Build Time | Assessment |
|------------|------------|
| < 100ms | Excellent |
| 100-500ms | Good |
| 500ms-2s | Acceptable |
| > 2s | Consider optimization |

### Performance Tips

1. **Narrow @source paths** - More specific = faster builds
2. **Use incremental builds** - `--watch` mode is much faster
3. **Exclude node_modules** - Don't scan dependencies
4. **Use faster disk** - SSD > HDD significantly

## Step 7: Generate Report

```text
## Tailwind CSS Optimization Report

**Generated:** [date]
**Project:** [path]

### Bundle Size

| Metric | Size | Assessment |
|--------|------|------------|
| Development | XXX KB | - |
| Production | XXX KB | [assessment] |
| Gzipped | XXX KB | [assessment] |

### Source Coverage

| Source Pattern | Files Found | Status |
|----------------|-------------|--------|
| `./src/**/*.jsx` | 45 | OK |
| `./templates/**/*.templ` | 12 | OK |
| `./components/**/*.html` | 0 | Warning: No files |

### Class Usage

| Metric | Count |
|--------|-------|
| Unique classes in templates | XXX |
| Classes in generated CSS | XXX |
| Potentially unused | XXX |

### CSS Variables

| Category | Count | Status |
|----------|-------|--------|
| Total variables | XXX | - |
| Color variables | XXX | [status] |
| Unused estimates | XXX | [status] |

### Build Performance

| Metric | Value |
|--------|-------|
| Build time | XXX ms |
| Incremental | XXX ms |

### Recommendations

**High Priority:**
1. [Critical optimizations]

**Medium Priority:**
2. [Helpful optimizations]

**Low Priority:**
3. [Nice-to-have optimizations]

### Quick Wins

```bash
# Commands to apply recommended optimizations
[commands]
```
```

## Step 8: Apply Optimizations (if --fix)

When `--fix` flag is present:

1. **Add missing @source** - For uncovered template directories
2. **Remove overly broad sources** - Replace `**/*` with specific patterns
3. **Update build scripts** - Add `--minify` for production

**Do NOT auto-fix:**
- Class removal (may break dynamic classes)
- Theme variable removal (may be used elsewhere)
- Source path reduction (may cause missing classes)

## Notes

- Always test after optimization changes
- Some "unused" CSS is intentional (resets, future features)
- Gzipped size matters most for production
- Use browser DevTools "Coverage" tab for runtime analysis
- Consider code-splitting CSS for large applications
