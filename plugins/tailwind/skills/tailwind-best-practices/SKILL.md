---
name: tailwind-best-practices
description: "Tailwind CSS v4 guidance: utility-first patterns, @theme directive for color/spacing/font config, @source for content paths, dark mode, responsive design, oklch colors, custom variants, v4 vs v3 differences. Use when user writes Tailwind utility classes, configures @theme or @source in CSS, asks about v4 syntax, or styles components."
---

# Tailwind CSS v4 Best Practices

Use the bundled references for Tailwind CSS v4 guidance. Consult the linked official documentation when current upstream behavior matters.

## Reference Files

Read the relevant file for detailed patterns, code examples, and documentation URLs:

### `docs-urls.md` — Official Documentation URLs
URL tables organized by category (Getting Started, Core Concepts, Layout, Spacing, Sizing, Typography, Backgrounds & Borders, Effects, Transforms & Animation, Interactivity). Use with WebFetch when current upstream behavior needs verification.

### `v4-syntax.md` — Tailwind CSS v4 Core Syntax
**CRITICAL**: v4 changed significantly from v3. Covers `@import "tailwindcss"`, `@theme` directive for CSS-based configuration (colors, fonts, spacing), `@source` for detection, class-based `@custom-variant dark` plus `.dark` selectors, `@layer components` for extraction, and `@plugin` for plugins.

### `best-practices.md` — Best Practices
Class ordering convention (layout → spacing → sizing → typography → colors → effects → interactive), responsive design (mobile-first, breakpoint reference), component extraction rule (3+ times), theme variables over hardcoded values, accessibility (focus-visible, sr-only, contrast).

### `anti-patterns.md` — v4 Anti-Patterns
v3 → v4 migration table (tailwind.config.js → @theme, @tailwind → @import, etc.), common mistakes (inline styles, px values, duplicate/conflicting utilities).

### `quick-reference.md` — Quick Reference
Response guidelines for helping with Tailwind, example response flow, spacing scale table, common utility patterns (centered content, card, responsive grid, truncation, gradient, fixed header).

---

*For the latest documentation, always refer to https://tailwindcss.com/docs*
