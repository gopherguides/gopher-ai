# tailwind

Tailwind CSS v4 development tools for initialization, auditing, migration, and optimization.

## Installation

Claude Code:

```bash
/plugin install tailwind@gopher-ai
```

Codex, after registering the gopher-ai marketplace:

```bash
codex plugin add tailwind@gopher-ai
```

## Workflow surfaces

| Workflow | Claude Code | Codex | Behavior |
|----------|-------------|-------|----------|
| Initialize | `/tailwind-init [path]` | `$tailwind:init [path]` | Explicit-only on Codex; installs and configures Tailwind v4 |
| Audit | `/tailwind-audit [path] [options]` | `$tailwind:audit [path] [options]` | Read-only by default; `--fix` applies safe fixes |
| Migrate | `/tailwind-migrate [options]` | `$tailwind:migrate [options]` | Explicit-only on Codex; `--check` previews without changes |
| Optimize | `/tailwind-optimize [options]` | `$tailwind:optimize [options]` | Read-only by default; `--fix` applies safe optimizations |

The Tailwind `cancel-loop` workflow remains intentionally unsupported on Codex
because it controls Claude Code persistent-loop hooks.

## Skills (Auto-invoked)

### Tailwind Best Practices

Automatically applies Tailwind v4 patterns when:
- Writing HTML/templates with Tailwind classes
- Styling components or layouts
- Asking about Tailwind utilities or features
- Configuring theme customization

The skill provides:
- **Documentation references** - Bundled links to current Tailwind docs
- **v4 syntax guidance** - @theme, @source, @variant directives
- **Best practices** - Class ordering, component extraction, accessibility
- **Anti-patterns** - Warns against outdated v3 patterns

The skill uses the official documentation links in
`skills/tailwind-best-practices/docs-urls.md` for current version guidance.

## Tailwind v4 Quick Reference

### Installation

```bash
npm install -D tailwindcss @tailwindcss/cli
```

### CSS Entry Point

```css
@import "tailwindcss";

@source "./templates/**/*.templ";
@source "./src/**/*.{js,jsx,ts,tsx}";

@theme {
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
}

@custom-variant dark (&:where(.dark, .dark *));

.dark {
  --color-background: oklch(0.145 0 0);
  --color-foreground: oklch(0.985 0 0);
}
```

### Build Commands

```bash
# Development (watch mode)
npx @tailwindcss/cli -i input.css -o output.css --watch

# Production (minified)
npx @tailwindcss/cli -i input.css -o output.css --minify
```

## Key v4 Changes

| v3 | v4 |
|----|-----|
| `tailwind.config.js` | CSS `@theme { }` directive |
| `@tailwind base/components/utilities` | `@import "tailwindcss"` |
| `content: [...]` | `@source "..."` |
| `darkMode: 'class'` | `@custom-variant dark (...)` plus `.dark { }` overrides |

## Integration Options

| Method | Package | Best For |
|--------|---------|----------|
| CLI | `@tailwindcss/cli` | Most projects, Go/Templ |
| Vite | `@tailwindcss/vite` | Vite-based projects |
| PostCSS | `@tailwindcss/postcss` | Existing PostCSS pipelines |

## Examples

Claude Code:

```bash
# Initialize in current project
/tailwind-init

# Initialize with specific path
/tailwind-init ./my-app

# Audit for issues
/tailwind-audit

# Audit and auto-fix
/tailwind-audit --fix

# Migrate from v3
/tailwind-migrate

# Preview migration without changes
/tailwind-migrate --check

# Analyze CSS output
/tailwind-optimize

# Generate detailed report
/tailwind-optimize --report
```

Codex:

```text
$tailwind:init
$tailwind:init ./my-app
$tailwind:audit
$tailwind:audit --fix
$tailwind:migrate --check
$tailwind:optimize --report
```

## Requirements

- **Node.js 18+** - Required for Tailwind v4
- **npm** - Or compatible package manager (yarn, pnpm, bun)

## Resources

- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [v4 Upgrade Guide](https://tailwindcss.com/docs/upgrade-guide)
- [oklch Color Picker](https://oklch.com/)

## License

MIT - see [LICENSE](../../LICENSE)
