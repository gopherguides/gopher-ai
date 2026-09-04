---
argument-hint: "[path] [--report|--fix|--verbose]"
description: "Analyze and optimize Tailwind CSS output"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(node:*)", "Bash(grep:*)", "Bash(ls:*)", "Bash(fd:*)", "Bash(wc:*)", "Bash(gzip:*)", "Bash(comm:*)", "Bash(sed:*)", "Bash(time:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Optimize Tailwind CSS

**If `$ARGUMENTS` is empty or not provided:**

Analyze Tailwind CSS output and provide optimization recommendations.

**Usage:** `/tailwind-optimize [path] [options]`

- `/tailwind-optimize` — quick analysis
- `/tailwind-optimize ./apps/storefront` — analyze one project or subtree
- `/tailwind-optimize ./src/app.css` — analyze a specific Tailwind entry
- `/tailwind-optimize --report` — detailed report
- `/tailwind-optimize --fix` — apply safe optimizations

**Analyzes:** bundle size (dev vs prod, gzipped) · source coverage (`@source` paths cover all templates) · unused classes (in CSS but not templates) · CSS variable bloat · build performance.

Proceed with optimization analysis.

---

**If `$ARGUMENTS` is provided:**

Parse arguments:

- **Path** — directory or file (default: current directory)
- `--report` — detailed markdown report
- `--fix` — apply safe optimizations
- `--verbose` — show all findings

Bind the requested or implicitly derived path to `<OPTIMIZE_TARGET>` as a
concrete normalized path. If no path was supplied, bind the current directory.
Stop with a clear error when the target does not exist. Resolve the containing
project or package root to `<PROJECT_ROOT>` for build configuration and local
dependency lookup, but never use `<PROJECT_ROOT>` as a replacement discovery
target.

Bind `<SUPPORTED_SOURCE_EXTENSIONS>` once to the project's complete source set
and use it for target validation, directory discovery, `@source` verification,
`<TEMPLATE_FILES>`, class inventory, reporting, and fixes. The baseline set is:

`js`, `jsx`, `ts`, `tsx`, `html`, `htm`, `templ`, `vue`, `svelte`, `astro`,
`php`, `blade.php`, `erb`, `hbs`, `md`, `mdx`, `ejs`, `twig`, `liquid`, `njk`,
`nunjucks`, `pug`, `jade`, `haml`, `slim`, `razor`, and `cshtml`.

This baseline is not an allowlist. Tailwind scans non-ignored plain-text source
files, so add every other text source selected by an `@source` rule or the
chosen build integration. Exclude CSS, binary files, lockfiles,
`node_modules`, and ignored paths using Tailwind's source-detection rules.
Never omit a target-associated source merely because its extension is absent
from the baseline.

When `<OPTIMIZE_TARGET>` is a directory, limit CSS entries, generated
artifacts, and templates to that subtree. When it is a CSS file, bind that file
directly to `<CSS_ENTRY>` and derive `<TEMPLATE_FILES>` only from its `@source`
rules and the selected integration's content scope. When it is a supported
template file, use that file as the complete `<TEMPLATE_FILES>` set and locate
only the Tailwind entry associated with its containing integration. For any
other file type, stop with a clear unsupported-target error.
Retain the complete `<TEMPLATE_FILES>` set for every later analysis and fix;
do not widen discovery to `.`.

## Loop Initialization

!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "tailwind-optimize" "COMPLETE"; fi`

## Step 1: Find CSS Files

```bash
grep -rl '@import.*tailwindcss' --include="*.css" "<OPTIMIZE_TARGET>" 2>/dev/null
fd -e css "<OPTIMIZE_TARGET>" 2>/dev/null
```

Use the selected integration's build configuration to identify the primary
Tailwind entry among the target-scoped files. Bind the selected Tailwind CSS entry to `<CSS_ENTRY>`.
If multiple target-associated candidates remain, ask which entry to analyze.
Bind an existing built artifact to `<GENERATED_CSS>`
only when the selected integration associates it with `<CSS_ENTRY>`; otherwise
leave it unavailable and report that limitation. Never select an entry or
artifact from an unrelated project merely because it is beneath
`<PROJECT_ROOT>`.

Choose a unique directory under the active temporary directory and bind its
concrete path to `<TEMP_DIR>` for every disposable analysis file.

## Step 2: Measure Bundle Size

Use the first safe measurement path available.

### Local CLI Measurement

Check for the v4 CLI package itself rather than a potentially v3-owned shared
binary:

```bash
ls "<PROJECT_ROOT>/node_modules/@tailwindcss/cli/package.json" 2>/dev/null
```

When it exists, read `node_modules/@tailwindcss/cli/package.json`, select its
`bin` string or `tailwindcss` bin entry, and resolve that relative path against
the package directory. Verify that the resolved entry remains inside
`<PROJECT_ROOT>/node_modules/@tailwindcss/cli`, exists, and is a file. Bind its
concrete path to `<LOCAL_CLI_ENTRY>`; otherwise treat the CLI as unavailable.

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
fd -e css "<OPTIMIZE_TARGET>" 2>/dev/null
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
fd -e js -e jsx -e ts -e tsx -e html -e htm -e templ -e vue -e svelte -e astro -e php -e erb -e hbs -e md -e mdx -e ejs -e twig -e liquid -e njk -e nunjucks -e pug -e jade -e haml -e slim -e razor -e cshtml "<OPTIMIZE_TARGET>" 2>/dev/null | wc -l
fd -e js -e jsx -e ts -e tsx -e html -e htm -e templ -e vue -e svelte -e astro -e php -e erb -e hbs -e md -e mdx -e ejs -e twig -e liquid -e njk -e nunjucks -e pug -e jade -e haml -e slim -e razor -e cshtml "<OPTIMIZE_TARGET>" 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn
grep '@source' "<CSS_ENTRY>"
```

Use those commands for the baseline inventory, then add any other target-scoped
plain-text sources selected by `@source` or the build integration before
binding `<TEMPLATE_FILES>`.

For a file target, replace the discovery commands with direct inspection of
the bound `<CSS_ENTRY>` or `<TEMPLATE_FILES>` described above. In all cases,
bind the complete target-scoped result to `<TEMPLATE_FILES>` and use that exact
set below.

For each `@source` pattern, verify files are found:

```bash
fd -e js -e jsx -e ts -e tsx -e html -e htm -e templ -e vue -e svelte -e astro -e php -e erb -e hbs -e md -e mdx -e ejs -e twig -e liquid -e njk -e nunjucks -e pug -e jade -e haml -e slim -e razor -e cshtml "<RESOLVED_SOURCE_DIRECTORY>" 2>/dev/null | wc -l
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

Tailwind scans source files as plain text and does not evaluate interpolation.
Build the static class inventory from every file in `<TEMPLATE_FILES>` without
executing project code. Pass `"<TEMPLATE_FILES>"` as the exact bound input set
to the chosen read-only parser rather than rediscovering files. Recognize both
`class` and `className` values in these forms:

- double-quoted literals: `class="..."` and `className="..."`
- single-quoted literals: `class='...'` and `className='...'`
- interpolation-free backtick literals, including JSX expression wrappers:
  ``className={`...`}``
- JSX/TSX expression wrappers around static quoted strings, such as
  `className={'...'}`

Split only decoded static literal values on whitespace and write their unique
tokens to `<TEMP_DIR>/used-classes.txt`. Also retain statically recognizable
utility candidates elsewhere in JavaScript or template source because
Tailwind's scanner is not limited to class attributes.

Report every concatenation, conditional expression, helper call, or backtick
literal containing `${...}` as a dynamic class expression requiring manual
review. Do not treat fragments of a dynamic expression as literal classes. If
any unresolved dynamic expression exists, exclude it from used and unused
counts and label the CSS-only difference as "not observed in static source",
not "unused". Do not make an unused-class conclusion for the affected source
scope until its dynamic candidates are enumerated or safelisted.

After building the static inventory, parse `<GENERATED_CSS>` with an already
available standards-compliant CSS selector parser or a read-only equivalent
that provides the same guarantees. Traverse every qualified rule and extract
complete class-selector identifiers from the selector syntax tree. CSS-unescape
each identifier before writing the complete unique set to
`<TEMP_DIR>/css-classes.txt`.

The extraction must preserve full utility identities such as
`hover:bg-red-500`, `w-1/2`, arbitrary values like `bg-[#123456]`, important
forms like `font-bold!`, and negative forms like `-mt-4`. Do not use a grep
character-class regex, truncate selector output, or compare raw escaped CSS
spelling with source tokens.

Do not install a parser solely for optimization analysis. If no available
parser or read-only capability can parse selectors and CSS-unescape class
identifiers correctly, report generated class count and CSS-only comparison as
unavailable. Continue with source coverage and the other safe metrics instead
of producing partial or false unused-class counts.

After the parser writes the complete class set, compare it with static source:

```bash
# CSS-only (unused only when no unresolved dynamic expressions exist)
comm -23 "<TEMP_DIR>/css-classes.txt" "<TEMP_DIR>/used-classes.txt"
```

**Note:** Some CSS-only classes may be used by third-party libraries or be
intentional base/reset styles. Dynamic expressions such as `bg-${color}-500`
are a reported limitation, never evidence that the corresponding CSS is
unused.

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

**Optimization target:** [concrete target]

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
| CSS classes not observed in static source | XXX |
| Dynamic class expressions requiring review | XXX |

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

Apply changes only to `<CSS_ENTRY>` and the selected integration associated
with `<OPTIMIZE_TARGET>`. Derive missing sources only from the complete
`<TEMPLATE_FILES>` set. Do not change another workspace or application found
under `<PROJECT_ROOT>`.

**Do NOT auto-fix:** class removal (may break dynamic classes); theme variable removal (may be used elsewhere); source-path reduction (may cause missing classes).

## Notes

- Always test after optimization changes
- Some "unused" CSS is intentional (resets, future features)
- Gzipped size matters most for production
- Use browser DevTools "Coverage" tab for runtime analysis

## Completion Criteria

DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:

1. Bundle size measured wherever a local CLI or existing generated CSS made it safely available; every unavailable metric has a recorded limitation
2. Source coverage analyzed for the complete target-scoped `<TEMPLATE_FILES>` set
3. Every supported source extension used the same complete discovery and analysis set
4. Static `class` and `className` literals in all supported quote forms were inventoried
5. Dynamic expressions were reported and excluded from unused-class conclusions
6. Generated class identifiers were fully parsed and CSS-unescaped, or their dependent metrics were marked unavailable
7. The report identifies the concrete `<OPTIMIZE_TARGET>` and excludes unrelated projects
8. If `--fix`: safe optimizations applied only to the selected target integration
9. No missing build dependency was installed solely for analysis

```
<done>COMPLETE</done>
```

**Safety:** if 15+ iterations without success, document blockers and ask.
