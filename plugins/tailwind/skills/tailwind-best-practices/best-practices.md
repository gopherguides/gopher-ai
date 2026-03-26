## Best Practices

### Class Ordering Convention

Order utilities consistently for readability:

**Order:** layout -> spacing -> sizing -> typography -> colors -> effects -> interactive

```html
<!-- Good: Logical order -->
<div class="flex items-center gap-4 p-4 w-full text-sm text-gray-700 bg-white shadow-sm hover:bg-gray-50 transition-colors">

<!-- Bad: Random order -->
<div class="hover:bg-gray-50 flex bg-white p-4 text-sm shadow-sm w-full gap-4 items-center text-gray-700 transition-colors">
```

### Responsive Design

Mobile-first: base styles for mobile, add breakpoints for larger screens.

```html
<!-- Mobile first -->
<div class="w-full md:w-1/2 lg:w-1/3">

<!-- Breakpoints -->
sm: 640px   <!-- Small devices -->
md: 768px   <!-- Medium devices -->
lg: 1024px  <!-- Large devices -->
xl: 1280px  <!-- Extra large -->
2xl: 1536px <!-- 2X large -->
```

### Component Extraction Rule

Extract when a class combination appears **3+ times**:

```css
/* Instead of repeating in HTML */
@layer components {
  .flex-center {
    @apply flex items-center justify-center;
  }
  .text-muted {
    @apply text-sm text-muted-foreground;
  }
}
```

### Use Theme Variables

Always prefer theme variables over hardcoded values:

```html
<!-- Good: Uses theme variable -->
<div class="bg-primary text-primary-foreground">

<!-- Bad: Hardcoded color -->
<div class="bg-[#3b82f6] text-white">
```

### Accessibility

```html
<!-- Focus states -->
<button class="focus-visible:ring-2 focus-visible:ring-primary focus-visible:outline-none">

<!-- Screen reader only -->
<span class="sr-only">Close menu</span>

<!-- Ensure contrast -->
<!-- Use oklch colors with sufficient lightness difference -->
```
