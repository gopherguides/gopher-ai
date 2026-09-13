---
name: templui
description: "Version-aware templUI v1 and shadcn-templ v2 component guidance for Go/templ apps. Use for component installation, UI blocks, Script() setup, HTML-to-templ conversion, or Go-to-JavaScript interpolation. Offers an upgrade when legacy templUI is encountered. Skips generic HTMX issues and full goilerplate application generation."
---

# templUI and shadcn-templ

## Select the generation first

Inspect `go.mod`, component imports, `.templui.json`, `components.json`, and local component
source before selecting examples or installing dependencies. Copied v1 components may have
no module dependency; `components.json` alone is not enough without its schema and provenance.

- **Legacy:** `github.com/templui/templui`, `.templui.json`, v1 component source, or original
  templUI Pro/goilerplate v1–v2 blocks. Ask whether to upgrade before dependent edits.
- **Current:** `github.com/axadrn/shadcn-templ/v2` or shadcn-templ v2 configuration/source.
  Read [shadcn-templ.md](shadcn-templ.md); the v1 examples below do not apply automatically.
- **Mixed/unknown:** inspect the actual APIs and ask which generation is the target.

Whenever a new task encounters legacy usage, ask:

> This uses legacy templUI v1. Would you like to upgrade to shadcn-templ, or keep v1 for this task?

Use the active surface's question UI when available and wait before edits that depend on
the answer. Read-only inspection may continue. Honor an explicit choice already made in
this task; ask again when a later task encounters legacy usage. If upgrading, explain the
component, CSS, and JavaScript changes and agree on the migration scope before editing.
Do not interpret a UI upgrade as permission to regenerate the app with goilerplate.

For new projects, offer shadcn-templ and verify its current release status (the v2 docs
currently identify it as beta). If the user chooses v1, use the legacy references below.
Do not silently introduce v1 through an older scaffold template.

The original 222 premium blocks are frozen on v1 and distinct from the new public
[shadcn-templ blocks](https://shadcn-templ.com/blocks). If an installed private `templui-pro`
skill is available, use it for licensed legacy catalog navigation. Otherwise ask for the
user's authorized local library; do not invent premium source or vendor it into this plugin.

## Legacy v1 guidance

Use the following only after the user chooses to keep v1 for the current task.

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
Install, init, add components, force-update, list available. Choose the existing project’s module-import or CLI-copy workflow; they use different import paths.

### `script-templates.md` — Script() Templates (REQUIRED)
Components with JavaScript need Script() calls in base layout `<head>`. Lists all Script() imports (popover, dropdown, dialog, accordion, tabs, carousel, toast, clipboard), component dependency table, and troubleshooting for non-working components.

### `conversion-and-audit.md` — Converting Sites & Auditing
Converting HTML/React/Vue to Go/Templ: process, syntax mapping, package structure. Templ syntax quick reference (props, conditionals, loops, composition). Audit checklist for Script() calls, CLI installation, consistency, dark mode, responsive. Import patterns and troubleshooting guide. Resource links for templUI, HTMX+Alpine, and templ docs.
