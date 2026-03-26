## Tailwind CSS v4 Core Syntax

**CRITICAL**: Tailwind v4 changed significantly from v3. Always use v4 syntax.

### CSS Entry Point

```css
@import "tailwindcss";
```

This single import replaces the old `@tailwind base; @tailwind components; @tailwind utilities;` directives.

### Theme Configuration (@theme directive)

All theme customization is done in CSS, not JavaScript:

```css
@theme {
  /* Colors - use oklch for better color manipulation */
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
  --color-secondary: oklch(0.5 0.02 250);
  --color-secondary-foreground: oklch(1 0 0);

  /* Semantic colors */
  --color-background: oklch(1 0 0);
  --color-foreground: oklch(0.145 0 0);
  --color-muted: oklch(0.95 0 0);
  --color-muted-foreground: oklch(0.4 0 0);
  --color-border: oklch(0.9 0 0);
  --color-destructive: oklch(0.55 0.25 25);

  /* Font families */
  --font-sans: "Inter", ui-sans-serif, system-ui, sans-serif;
  --font-mono: "Fira Code", ui-monospace, monospace;

  /* Custom spacing (extends default scale) */
  --spacing-18: 4.5rem;
  --spacing-22: 5.5rem;

  /* Custom border radius */
  --radius-4xl: 2rem;
}
```

### Source Detection (@source directive)

Tailwind auto-detects most template files. Use `@source` for custom paths:

```css
@source "./templates/**/*.templ";
@source "./components/**/*.html";
@source "./src/**/*.{js,jsx,ts,tsx,vue,svelte}";
```

### Dark Mode (@variant directive)

```css
@variant dark {
  --color-background: oklch(0.145 0 0);
  --color-foreground: oklch(0.985 0 0);
  --color-muted: oklch(0.25 0 0);
  --color-muted-foreground: oklch(0.6 0 0);
  --color-border: oklch(0.3 0 0);
  --color-card: oklch(0.205 0 0);
}
```

### Component Layer (@layer components)

Extract repeated patterns:

```css
@layer components {
  .btn {
    @apply px-4 py-2 rounded-lg font-medium transition-colors;
  }
  .btn-primary {
    @apply btn bg-primary text-primary-foreground hover:bg-primary/90;
  }
  .btn-secondary {
    @apply btn bg-secondary text-secondary-foreground hover:bg-secondary/90;
  }
  .card {
    @apply p-6 bg-card rounded-xl border border-border shadow-sm;
  }
}
```

### Plugins (@plugin directive)

```css
@plugin "@tailwindcss/typography";
```
