## v4 Anti-Patterns to Avoid

### DO NOT USE (v3 patterns):

| Wrong (v3) | Correct (v4) |
|------------|--------------|
| `tailwind.config.js` | CSS `@theme { }` directive |
| `@tailwind base;` | `@import "tailwindcss";` |
| `@tailwind components;` | (included in import) |
| `@tailwind utilities;` | (included in import) |
| `darkMode: 'class'` in config | `@variant dark { }` in CSS |
| `theme.extend.colors` in JS | `--color-*` in @theme |
| `content: [...]` in JS | `@source "..."` in CSS |

### Common Mistakes

```html
<!-- Wrong: Inline styles when utility exists -->
<div style="display: flex; gap: 1rem;">
<!-- Correct -->
<div class="flex gap-4">

<!-- Wrong: px values when scale exists -->
<div class="p-[16px]">
<!-- Correct -->
<div class="p-4">

<!-- Wrong: Duplicate utilities -->
<div class="p-4 p-6">
<!-- Correct -->
<div class="p-6">

<!-- Wrong: Conflicting utilities -->
<div class="flex block">
<!-- Correct: Choose one -->
<div class="flex">
```
