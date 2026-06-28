---
name: templui
description: "templUI component library for Go templ apps. templUI is vanilla JavaScript only - zero JS frameworks (per templui.io). Covers Script() setup, Go variable interpolation into inline JavaScript, HTML-to-templ conversion, HTMX integration, and optional Alpine.js as a separate app-level state layer. Use when user pastes templUI/templ code, builds templUI components, asks 'how do I add an icon/button/dialog/dropdown' in templ, or interpolates Go state into client-side scripts. SKIP generic htmx issues with no templUI/component context."
---

# templUI Best Practices

Apply templUI patterns when building Go/Templ web applications.

## CRITICAL: templUI Uses Vanilla JavaScript (Zero JS Frameworks)

Per [templui.io](https://templui.io/): "Zero JS frameworks — Just vanilla. Just fast." templUI components use **vanilla JavaScript via Script() templates** for all interactivity (popovers, dropdowns, dialogs, tabs, etc.). They do NOT depend on Alpine.js, React, Vue, or any other framework.

**Earlier versions of templUI integrated with Alpine.js. That dependency has been removed.** If you find documentation or code referencing `x-data`/`x-show`/`x-if` directives inside templUI components, it's stale.

## The Frontend Stack

| Tool | Purpose | Use For |
|------|---------|---------|
| **templUI** | Pre-built UI components (vanilla JS) | Dropdowns, dialogs, tabs, sidebars, popovers, accordions |
| **HTMX** | Server-driven interactions | AJAX, form submissions, partial page updates, live search |
| **Alpine.js** *(optional)* | Lightweight client-side state | Toggles, animations, client-side filtering, transitions — used **alongside** templUI, not as an integration. Skip if you don't need a reactive state layer beyond what HTMX + Script() provide. |
| **Floating UI** | Positioning primitive (used internally by templUI) | Tooltips, popovers, dropdowns — usually transparent to users |

---

## Reference Files

Read the relevant file for detailed patterns, code examples, and troubleshooting:

### `htmx-alpine-integration.md` — HTMX + Alpine.js (optional, separate from templUI)
For apps that choose to add Alpine.js as a client-side state layer **alongside** templUI. Read only when Alpine is actually in use. Covers: when to use HTMX vs Alpine vs combined, Alpine-Morph extension for state preservation across swaps, `htmx.process()` for Alpine conditionals, triggering HTMX from Alpine. **Skip if your app uses templUI + HTMX + Script() without Alpine** — that's templUI's recommended setup.

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
