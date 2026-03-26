# Script() Templates - REQUIRED for Interactive Components

Components with JavaScript include a `Script()` template function. **You MUST add these to your base layout's `<head>`:**

```templ
// In your base layout <head>:
@popover.Script()      // Required for: popover, dropdown, tooltip, combobox
@dropdown.Script()     // Required for: dropdown
@dialog.Script()       // Required for: dialog, sheet, alertdialog
@accordion.Script()    // Required for: accordion, collapsible
@tabs.Script()         // Required for: tabs
@carousel.Script()     // Required for: carousel
@toast.Script()        // Required for: toast/sonner
@clipboard.Script()    // Required for: copybutton
```

## Component Dependencies

| Component | Requires Script() from |
|-----------|----------------------|
| dropdown | dropdown, popover |
| tooltip | popover |
| combobox | popover |
| sheet | dialog |
| alertdialog | dialog |
| collapsible | accordion |

## Troubleshooting

**If a component doesn't work (no click events, no positioning), check that:**
1. The Script() template is called in the layout
2. The component was installed via CLI (not manually copied)
3. All dependency scripts are included
