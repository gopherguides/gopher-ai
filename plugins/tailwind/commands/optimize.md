---
argument-hint: "[--report|--fix]"
description: "Analyze and optimize Tailwind CSS output"
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_utilities"]
---

# Optimize Tailwind CSS

**If `$ARGUMENTS` is empty or not provided:**

Analyze Tailwind CSS output and provide optimization recommendations.

**Usage:** `/tailwind-optimize [options]`

- `/tailwind-optimize` — quick analysis
- `/tailwind-optimize --report` — detailed report
- `/tailwind-optimize --fix` — apply safe optimizations

**Analyzes:** bundle size (dev vs prod, gzipped) · source coverage (`@source` paths cover all templates) · unused classes (in CSS but not templates) · CSS variable bloat · build performance.

Proceed with optimization analysis.

---

**If `$ARGUMENTS` is provided:**

Parse arguments: `--report` (detailed markdown report), `--fix` (apply safe optimizations), `--verbose` (show all findings).

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-optimize" "COMPLETE"; fi`

## Step 1: Find CSS Files

```bash
grep -rl '@import.*tailwindcss' --include="*.css" . 2>/dev/null
ls **/output.css dist/**/*.css build/**/*.css public/**/*.css 2>/dev/null
```

## Step 2: Measure Bundle Size

```bash
# Dev build (no minification)
npx @tailwindcss/cli -i input.css -o /tmp/dev-output.css 2>&1
wc -c /tmp/dev-output.css

# Prod build (minified) + gzip estimate
npx @tailwindcss/cli -i input.css -o /tmp/prod-output.css --minify 2>&1
wc -c /tmp/prod-output.css
gzip -c /tmp/prod-output.css | wc -c
```

**Size benchmarks (gzipped):**

| Range | Assessment |
|-------|------------|
| < 10 KB | Excellent — highly optimized |
| 10–25 KB | Good — normal for most apps |
| 25–50 KB | Acceptable — consider optimization |
| > 50 KB | Needs optimization |

Most Tailwind projects ship < 10 KB CSS gzipped.

## Step 3: Analyze Source Coverage

```bash
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -d 5 2>/dev/null | wc -l
fd -e html -e htm -e templ -e jsx -e tsx -e vue -e svelte -d 5 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn
grep '@source' input.css
```

For each `@source` pattern, verify files are found:

```bash
fd -e js -e jsx ./src 2>/dev/null | wc -l   # for @source "./src/**/*.{js,jsx}"
```

| Issue | Symptom | Fix |
|-------|---------|-----|
| Missing source | Classes not generated | Add `@source` for directory |
| Overly broad | Too much CSS generated | Use specific globs |
| Wrong path | Classes missing | Verify path exists |

## Step 4: Find Unused Classes

```bash
# Used classes in templates
grep -ohr 'class="[^"]*"' --include="*.html" --include="*.templ" --include="*.jsx" --include="*.tsx" . 2>/dev/null | \
  sed 's/class="//g' | sed 's/"//g' | tr ' ' '\n' | sort -u > /tmp/used-classes.txt

# Class names in generated CSS
grep -oE '\.[a-zA-Z][a-zA-Z0-9_-]*' output.css | sed 's/\.//' | sort -u > /tmp/css-classes.txt

# CSS-only (potentially unused)
comm -23 /tmp/css-classes.txt /tmp/used-classes.txt | head -50
```

**Note:** Some "unused" classes may be: dynamically generated (`bg-${color}-500`); used by JavaScript; from third-party libraries; or base/reset styles (intentionally included).

## Step 5: CSS Variable Analysis

```bash
grep -c -- '--' output.css
grep -oE '--color-[a-z]+-[0-9]+' output.css | sort -u | wc -l
```

| Category | Expected | If higher |
|----------|----------|-----------|
| Color vars | 50–100 | Using full palette when subset would work |
| Spacing vars | 20–30 | Normal |
| Font vars | 5–10 | Normal |
| Animation vars | 10–20 | Normal |

**Reducing variable bloat:** define only needed colors in `@theme` (don't rely on the full Tailwind palette); use specific `@source` paths to generate only needed utilities.

## Step 6: Build Performance

```bash
time npx @tailwindcss/cli -i input.css -o output.css --minify 2>&1
```

| Build time | Assessment |
|------------|------------|
| < 100 ms | Excellent |
| 100–500 ms | Good |
| 500 ms – 2 s | Acceptable |
| > 2 s | Consider optimization |

**Tips:** narrow `@source` paths (more specific = faster); use `--watch` for incremental builds; exclude `node_modules`; SSD significantly faster than HDD.

## Step 7: Generate Report

```
## Tailwind CSS Optimization Report

### Bundle Size

| Metric | Size | Assessment |
|--------|------|------------|
| Development | XXX KB | — |
| Production | XXX KB | [assessment] |
| Gzipped | XXX KB | [assessment] |

### Source Coverage

| Source Pattern | Files Found | Status |
|----------------|-------------|--------|
| `./src/**/*.jsx` | 45 | OK |
| `./components/**/*.html` | 0 | Warning: No files |

### Class Usage

| Metric | Count |
|--------|-------|
| Unique classes in templates | XXX |
| Classes in generated CSS | XXX |
| Potentially unused | XXX |

### CSS Variables / Build Performance

[Per the categories above]

### Recommendations

**High Priority:** [Critical]
**Medium Priority:** [Helpful]
**Low Priority:** [Nice-to-have]
```

## Step 8: Apply Optimizations (if `--fix`)

Auto-apply: add missing `@source` for uncovered template directories; replace `**/*` with specific patterns; add `--minify` to production build scripts.

**Do NOT auto-fix:** class removal (may break dynamic classes); theme variable removal (may be used elsewhere); source-path reduction (may cause missing classes).

## Notes

- Always test after optimization changes
- Some "unused" CSS is intentional (resets, future features)
- Gzipped size matters most for production
- Use browser DevTools "Coverage" tab for runtime analysis

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Bundle size measured (dev and prod)
2. Source coverage analyzed
3. Optimization report generated
4. If `--fix`: safe optimizations applied

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
