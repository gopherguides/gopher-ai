## Response Guidelines

When helping with Tailwind CSS:

1. **Always use v4 syntax** - No tailwind.config.js, use @theme in CSS
2. **Use MCP tools first** - Get current documentation before answering
3. **Prefer theme variables** - `bg-primary` not `bg-blue-500`
4. **Include accessibility** - Add focus-visible, sr-only where appropriate
5. **Show complete examples** - Include all necessary classes
6. **Explain class choices** - Help users understand why

### Example Response Flow

**User:** "How do I create a button with hover effect?"

**Response:**
1. Use `mcp__tailwindcss__get_tailwind_utilities` for button-related utilities
2. Provide example with proper class ordering:

```html
<button class="px-4 py-2 rounded-lg font-medium bg-primary text-primary-foreground hover:bg-primary/90 focus-visible:ring-2 focus-visible:ring-primary focus-visible:outline-none transition-colors">
  Click me
</button>
```

3. Explain the classes used
4. Suggest extracting to component if used multiple times

---

## Quick Reference

### Spacing Scale
| Class | Size |
|-------|------|
| 1 | 0.25rem (4px) |
| 2 | 0.5rem (8px) |
| 3 | 0.75rem (12px) |
| 4 | 1rem (16px) |
| 5 | 1.25rem (20px) |
| 6 | 1.5rem (24px) |
| 8 | 2rem (32px) |
| 10 | 2.5rem (40px) |
| 12 | 3rem (48px) |
| 16 | 4rem (64px) |

### Common Patterns

```html
<!-- Centered content -->
<div class="flex items-center justify-center">

<!-- Card -->
<div class="p-6 bg-card rounded-xl border border-border shadow-sm">

<!-- Responsive grid -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">

<!-- Truncated text -->
<p class="truncate">Long text that will be truncated...</p>

<!-- Gradient background -->
<div class="bg-gradient-to-r from-primary to-secondary">

<!-- Fixed header -->
<header class="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-sm">
```

---

*For the latest documentation, always refer to https://tailwindcss.com/docs*
