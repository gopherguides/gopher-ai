---
name: tailwind-best-practices
description: Tailwind CSS guidance: utility-first patterns, theme/color config, dark mode, responsive design, v4 syntax, content/source paths. Trigger for any Tailwind-related styling question.

---

# Tailwind CSS v4 Best Practices

You have access to up-to-date Tailwind CSS documentation via MCP tools. Use these tools to provide accurate, current information.

## Available MCP Tools

### `mcp__tailwindcss__search_tailwind_docs`
Use when user asks about any Tailwind feature, utility, or concept.

### `mcp__tailwindcss__get_tailwind_utilities`
Use when user needs utility classes for a specific CSS property.

### `mcp__tailwindcss__get_tailwind_colors`
Use when user asks about colors, palettes, or color-related utilities.

### `mcp__tailwindcss__convert_css_to_tailwind`
Use when user has CSS they want to convert to Tailwind utility classes.

### `mcp__tailwindcss__generate_component_template`
Use when user needs a component template with Tailwind styling.

---

## Reference Files

Read the relevant file for detailed patterns, code examples, and documentation URLs:

### `docs-urls.md` — Official Documentation URLs
URL tables organized by category (Getting Started, Core Concepts, Layout, Spacing, Sizing, Typography, Backgrounds & Borders, Effects, Transforms & Animation, Interactivity). Use with WebFetch when MCP tools are unavailable.

### `v4-syntax.md` — Tailwind CSS v4 Core Syntax
**CRITICAL**: v4 changed significantly from v3. Covers `@import "tailwindcss"`, `@theme` directive for CSS-based configuration (colors, fonts, spacing), `@source` for detection, `@variant dark` for dark mode, `@layer components` for extraction, `@plugin` for plugins.

### `best-practices.md` — Best Practices
Class ordering convention (layout → spacing → sizing → typography → colors → effects → interactive), responsive design (mobile-first, breakpoint reference), component extraction rule (3+ times), theme variables over hardcoded values, accessibility (focus-visible, sr-only, contrast).

### `anti-patterns.md` — v4 Anti-Patterns
v3 → v4 migration table (tailwind.config.js → @theme, @tailwind → @import, etc.), common mistakes (inline styles, px values, duplicate/conflicting utilities).

### `quick-reference.md` — Quick Reference
Response guidelines for helping with Tailwind, example response flow, spacing scale table, common utility patterns (centered content, card, responsive grid, truncation, gradient, fixed header).

---

*For the latest documentation, always refer to https://tailwindcss.com/docs*
