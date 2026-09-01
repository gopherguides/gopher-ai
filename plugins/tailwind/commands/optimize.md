---
argument-hint: "[--report|--fix]"
description: "Analyze and optimize Tailwind CSS output"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(node:*)", "Bash(grep:*)", "Bash(ls:*)", "Bash(fd:*)", "Bash(wc:*)", "Bash(gzip:*)", "Bash(comm:*)", "Bash(sed:*)", "Bash(time:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "mcp__tailwindcss__search_tailwind_docs", "mcp__tailwindcss__get_tailwind_utilities"]
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

Use the selected integration's build configuration to identify the primary
Tailwind entry among the discovered files. Bind the selected Tailwind CSS entry to `<CSS_ENTRY>`. If multiple candidates remain, ask which entry to analyze. Bind an existing built artifact to `<GENERATED_CSS>` when one can be identified; otherwise leave it unavailable and report that limitation.

Choose a unique directory under the active temporary directory and bind its
concrete path to `<TEMP_DIR>` for every disposable analysis file.

## Step 2: Measure Bundle Size

Use the first safe measurement path available.

### Local CLI Measurement

Check for the v4 CLI package itself rather than a potentially v3-owned shared
binary:

```bash
ls node_modules/@tailwindcss/cli/package.json 2>/dev/null
```

When it exists, read `node_modules/@tailwindcss/cli/package.json`, select its
`bin` string or `tailwindcss` bin entry, and resolve that relative path against
the package directory. Verify that the resolved entry remains inside
`node_modules/@tailwindcss/cli`, exists, and is a file. Bind its concrete path
to `<LOCAL_CLI_ENTRY>`; otherwise treat the CLI as unavailable.

Choose a unique directory under the active temporary directory, replace
`<TEMP_DIR>` below with that concrete path, and write both measurements there
rather than into the project:

```bash
node "<LOCAL_CLI_ENTRY>" -i "<CSS_ENTRY>" -o "<TEMP_DIR>/dev-output.css" 2>&1
wc -c "<TEMP_DIR>/dev-output.css"

node "<LOCAL_CLI_ENTRY>" -i "<CSS_ENTRY>" -o "<TEMP_DIR>/prod-output.css" --minify 2>&1
wc -c "<TEMP_DIR>/prod-output.css"
gzip -c "<TEMP_DIR>/prod-output.css" | wc -c
```

After a successful local CLI build, bind
`<TEMP_DIR>/prod-output.css` to `<GENERATED_CSS>` for the generated-class and
CSS-variable checks below.

Do not install `@tailwindcss/cli` solely for measurement.

### Existing Generated CSS Measurement

When the project uses Vite or PostCSS without a local Tailwind CLI, inspect
existing generated CSS artifacts without rebuilding or overwriting them:

```bash
fd -e css . dist build public .next 2>/dev/null
wc -c "<GENERATED_CSS>"
gzip -c "<GENERATED_CSS>" | wc -c
```

Use project configuration and file names to distinguish development and
production artifacts. If only one generated artifact exists, report the
available size and mark the other measurement unavailable. If no local CLI or
generated CSS is available, record the measurement limitation and continue
with source coverage and configuration analysis.

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
grep '@source' "<CSS_ENTRY>"
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

Use the generated CSS selected in Step 2. If no generated CSS is safely
available, skip the generated-class comparison, record the limitation, and
continue with template class inventory.

```bash
# Used classes in templates
grep -ohr 'class="[^"]*"' --include="*.html" --include="*.templ" --include="*.jsx" --include="*.tsx" . 2>/dev/null | \
  sed 's/class="//g' | sed 's/"//g' | tr ' ' '\n' | sort -u > "<TEMP_DIR>/used-classes.txt"

# Class names in generated CSS
grep -oE '\.[a-zA-Z][a-zA-Z0-9_-]*' "<GENERATED_CSS>" | sed 's/\.//' | sort -u > "<TEMP_DIR>/css-classes.txt"

# CSS-only (potentially unused)
comm -23 "<TEMP_DIR>/css-classes.txt" "<TEMP_DIR>/used-classes.txt" | head -50
```

**Note:** Some "unused" classes may be: dynamically generated (`bg-${color}-500`); used by JavaScript; from third-party libraries; or base/reset styles (intentionally included).

## Step 5: CSS Variable Analysis

Run generated-CSS checks only against the artifact selected in Step 2. If none
is available, report these metrics as unavailable rather than building over a
project output file.

```bash
grep -c -- '--' "<GENERATED_CSS>"
grep -oE '--color-[a-z]+-[0-9]+' "<GENERATED_CSS>" | sort -u | wc -l
```

| Category | Expected | If higher |
|----------|----------|-----------|
| Color vars | 50–100 | Using full palette when subset would work |
| Spacing vars | 20–30 | Normal |
| Font vars | 5–10 | Normal |
| Animation vars | 10–20 | Normal |

**Reducing variable bloat:** define only needed colors in `@theme` (don't rely on the full Tailwind palette); use specific `@source` paths to generate only needed utilities.

## Step 6: Build Performance

When a local Tailwind CLI is available, time a build into the temporary
directory selected in Step 2:

```bash
time node "<LOCAL_CLI_ENTRY>" -i "<CSS_ENTRY>" -o "<TEMP_DIR>/timed-output.css" --minify 2>&1
```

Without a local CLI, do not run a read-only Vite or PostCSS build that may
overwrite project artifacts. Record build timing as unavailable. With `--fix`,
run and time the selected integration's existing verification command after
applying changes, then report that project-build timing separately.

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

### Measurement Limitations

[Unavailable measurements and the missing local artifact or tool that prevented them]

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

1. Bundle size measured wherever a local CLI or existing generated CSS made it safely available; every unavailable metric has a recorded limitation
2. Source coverage analyzed
3. Optimization report generated
4. If `--fix`: safe optimizations applied
5. No missing build dependency was installed solely for analysis

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
