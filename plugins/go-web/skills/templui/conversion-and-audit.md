# Converting Sites to Templ/templUI

When converting HTML/React/Vue to Go/Templ:

## Conversion Process

1. Analyze existing UI patterns
2. Map to templUI base components
3. Convert syntax:
   - `class` stays as `class` in templ
   - `className` (React) -> `class`
   - React/Vue event handlers -> vanilla JS via Script() or HTMX
   - Dynamic content -> templ expressions `{ variable }` or `@component()`
4. **Add required Script() templates to layout**
5. Set up proper Go package structure

## Templ Syntax Quick Reference

```templ
package components

type ButtonProps struct {
    Text    string
    Variant string
}

templ Button(props ButtonProps) {
    <button class={ "btn", props.Variant }>
        { props.Text }
    </button>
}

// Conditional
if condition {
    <span>Shown</span>
}

// Loops
for _, item := range items {
    <li>{ item.Name }</li>
}

// Composition
@Header()
@Content() {
    // Children
}
```

---

## Auditing for Better Component Usage

**Audit Checklist:**
1. **Script() Templates**: Are all required Script() calls in the base layout?
2. **CLI Installation**: Were components added via `templui add` or manually copied?
3. **Component Consistency**: Same patterns using same components?
4. **Base Component Usage**: Custom code that could use templUI?
5. **Dark Mode**: Tailwind dark: variants used?
6. **Responsive**: Mobile breakpoints applied?

**Common Issues to Check:**
- Missing `@popover.Script()` -> dropdowns/tooltips don't open
- Missing `@dialog.Script()` -> dialogs/sheets don't work
- Manually copied components missing Script() template files

---

## Import Pattern

```go
import "github.com/templui/templui/components/button"
import "github.com/templui/templui/components/dropdown"
import "github.com/templui/templui/components/dialog"
```

---

## Troubleshooting

**JavaScript URL contains literal `{` or `%7B` (URL-encoded brace):**
Go expressions don't interpolate in `<script>` tags. Use data attributes:
```templ
// WRONG: <script>fetch(`/api/{ id }`)</script>
// RIGHT:
<button data-id={ id } onclick="doFetch(this.dataset.id)">
```
See the templ-interpolation.md reference for full details.

**Component not responding to clicks:**
1. Check Script() is in layout: `@dropdown.Script()`, `@popover.Script()`
2. Reinstall: `templui add -f dropdown popover`
3. Check browser console for JS errors

**Dropdown/Tooltip not positioning correctly:**
1. Ensure `@popover.Script()` is in layout (uses Floating UI)
2. Reinstall popover: `templui add -f popover`

**Dialog/Sheet not opening:**
1. Add `@dialog.Script()` to layout
2. Reinstall: `templui add -f dialog`

---

## Resources

**templUI:**
- Documentation: https://templui.io/docs
- GitHub: https://github.com/templui/templui

**HTMX + Alpine.js:**
- [HTMX and Alpine.js: How to combine two great, lean front ends](https://www.infoworld.com/article/3856520/htmx-and-alpine-js-how-to-combine-two-great-lean-front-ends.html)
- [Full-Stack Go App with HTMX and Alpine.js](https://ntorga.com/full-stack-go-app-with-htmx-and-alpinejs/)
- [When to Add Alpine.js to htmx](https://dev.to/alex_aslam/when-to-add-alpinejs-to-htmx-9bj)
- [HTMX Alpine-Morph Extension](https://htmx.org/extensions/alpine-morph/)

**Templ:**
- Templ Docs: https://templ.guide
