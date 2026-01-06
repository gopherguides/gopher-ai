# tailwind

Tailwind CSS v4 development tools for initialization, auditing, migration, and optimization.

## Installation

```bash
/plugin install tailwind@gopher-ai
```

Or install via marketplace:
```bash
/plugin marketplace add gopherguides/gopher-ai
```

## Commands

| Command | Description |
|---------|-------------|
| `/tailwind-init [path]` | Initialize Tailwind v4 in an existing project |
| `/tailwind-audit [path]` | Audit Tailwind usage for best practices |
| `/tailwind-migrate` | Migrate from Tailwind v3 to v4 |
| `/tailwind-optimize` | Analyze and optimize CSS output |

## Skills (Auto-invoked)

### Tailwind Best Practices

Automatically applies Tailwind v4 patterns when:
- Writing HTML/templates with Tailwind classes
- Styling components or layouts
- Asking about Tailwind utilities or features
- Configuring theme customization

The skill provides:
- **MCP-powered documentation** - Live access to current Tailwind docs
- **v4 syntax guidance** - @theme, @source, @variant directives
- **Best practices** - Class ordering, component extraction, accessibility
- **Anti-patterns** - Warns against outdated v3 patterns

## MCP Server Integration

This plugin includes the `tailwindcss-mcp-server` which provides:

| Tool | Purpose |
|------|---------|
| `search_tailwind_docs` | Search documentation for any topic |
| `get_tailwind_utilities` | Get utilities by category |
| `get_tailwind_colors` | Access color palette |
| `convert_css_to_tailwind` | Convert CSS to utilities |
| `generate_component_template` | Generate component templates |

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

@variant dark {
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
| `darkMode: 'class'` | `@variant dark { }` |

## Integration Options

| Method | Package | Best For |
|--------|---------|----------|
| CLI | `@tailwindcss/cli` | Most projects, Go/Templ |
| Vite | `@tailwindcss/vite` | Vite-based projects |
| PostCSS | `@tailwindcss/postcss` | Existing PostCSS pipelines |

## Examples

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

## Requirements

- **Node.js 18+** - Required for Tailwind v4
- **npm** - Or compatible package manager (yarn, pnpm, bun)

## Resources

- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [v4 Upgrade Guide](https://tailwindcss.com/docs/upgrade-guide)
- [oklch Color Picker](https://oklch.com/)

## License

MIT - see [LICENSE](../../LICENSE)
