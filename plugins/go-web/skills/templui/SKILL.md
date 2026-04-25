---
name: templui
description: templUI component library for Go templ apps. Use for templUI components, Script() setup, Go variable interpolation in JS, HTML-to-templ conversion, HTMX/Alpine integration.

---

# templUI & HTMX/Alpine Best Practices

Apply templUI patterns and HTMX/Alpine.js best practices when building Go/Templ web applications.

## The Frontend Stack

| Tool | Purpose | Use For |
|------|---------|---------|
| **HTMX** | Server-driven interactions | AJAX requests, form submissions, partial page updates, live search |
| **Alpine.js** | Client-side state & reactivity | Toggles, animations, client-side filtering, transitions, local state |
| **templUI** | Pre-built UI components | Dropdowns, dialogs, tabs, sidebars (uses vanilla JS via Script() templates) |

**Note:** templUI components use vanilla JavaScript (not Alpine.js) via Script() templates.

---

## Reference Files

Read the relevant file for detailed patterns, code examples, and troubleshooting:

### `htmx-alpine-integration.md` — HTMX + Alpine.js Integration
When to use HTMX vs Alpine vs combined. Key integration patterns: Alpine-Morph extension for state preservation across swaps, `htmx.process()` for Alpine conditionals, triggering HTMX from Alpine.

### `templ-interpolation.md` — CRITICAL: Templ Interpolation in JavaScript
Go expressions `{ value }` do NOT interpolate inside `<script>` tags. Five patterns to solve this:
1. **Data attributes** (recommended) — `data-*` attrs + `this.dataset`
2. **templ.JSFuncCall** — auto JSON-encodes, prevents XSS
3. **Double braces** — `{{ value }}` inside `<script>` tags
4. **templ.JSONString** — complex structs/maps via attributes or `templ.JSONScript`
5. **templ.OnceHandle** — ensures scripts render once in loops

Includes when-to-use table and common mistakes.

### `templui-cli.md` — templUI CLI Tool
Install, init, add components, force-update, list available. **Always use CLI to add/update components** — manual copies miss Script() templates.

### `script-templates.md` — Script() Templates (REQUIRED)
Components with JavaScript need Script() calls in base layout `<head>`. Lists all Script() imports (popover, dropdown, dialog, accordion, tabs, carousel, toast, clipboard), component dependency table, and troubleshooting for non-working components.

### `conversion-and-audit.md` — Converting Sites & Auditing
Converting HTML/React/Vue to Go/Templ: process, syntax mapping, package structure. Templ syntax quick reference (props, conditionals, loops, composition). Audit checklist for Script() calls, CLI installation, consistency, dark mode, responsive. Import patterns and troubleshooting guide. Resource links for templUI, HTMX+Alpine, and templ docs.
