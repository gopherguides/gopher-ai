# Client-Side Interactivity with templUI

Loaded on demand by /go-web:convert-to-go-project when the source project uses jQuery, React state, or other client-side JavaScript for UI interactivity (dropdowns, modals, sidebars, tabs).

templUI components handle client-side interactivity (dropdowns, modals, sidebars) via vanilla JavaScript
`Script()` templates. HTMX handles server communication. Together they replace heavy JavaScript frameworks.

**Important:** templUI does NOT use Alpine.js. Each interactive component has a `Script()` template that
must be included in your layout's `<head>`:

```templ
<head>
    @sidebar.Script()   // Required for: sidebar
    @dialog.Script()    // Required for: dialog, sheet, alertdialog
    @popover.Script()   // Required for: popover, dropdown, tooltip, combobox
    @accordion.Script() // Required for: accordion, collapsible
    @tabs.Script()      // Required for: tabs
</head>
```

**jQuery to templUI:**

```javascript
// jQuery (before)
$('.dropdown-toggle').click(function() {
  $(this).next('.dropdown-menu').toggle();
});
```

```templ
// templUI (after) - use dropdown component
@dropdown.Root() {
    @dropdown.Trigger() {
        <button>Toggle</button>
    }
    @dropdown.Content() {
        @dropdown.Item() { Option 1 }
        @dropdown.Item() { Option 2 }
    }
}
```

**React useState to templUI:**

```jsx
// React (before)
const [isOpen, setIsOpen] = useState(false);
return (
  <dialog open={isOpen}>...</dialog>
);
```

```templ
// templUI (after) - use dialog component
@dialog.Root() {
    @dialog.Trigger() {
        <button>Open Dialog</button>
    }
    @dialog.Content() {
        // Dialog content
    }
}
```

**Common templUI component patterns:**

| Pattern | templUI Component |
|---------|-------------------|
| Toggle visibility | `@dialog.Root()` with trigger/content |
| Dropdown menu | `@dropdown.Root()` |
| Sidebar navigation | `@sidebar.Root()` |
| Accordion/Collapsible | `@accordion.Root()` |
| Tabs | `@tabs.Root()` |
| Tooltip | `@tooltip.Root()` |
| Modal/Sheet | `@dialog.Root()` or `@sheet.Root()` |

> **CRITICAL: Templ Interpolation in JavaScript**
> Go expressions `{ value }` do NOT work inside `<script>` tags or inline event handler strings.
> - **Data attributes**: `data-id={ value }` + `this.dataset.id` in JS
> - **templ.JSFuncCall**: `onclick={ templ.JSFuncCall("fn", value) }` for onclick handlers
> - **Double braces**: `{{ value }}` (double braces) inside `<script>` tag strings
>
> If you see `%7B` or `%7D` in URLs, that's a literal `{` or `}` that wasn't interpolated.
