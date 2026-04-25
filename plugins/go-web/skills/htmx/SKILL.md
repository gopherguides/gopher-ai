---
name: htmx
description: htmx for Go/templ apps: hx-* attributes, swap strategies, triggers, OOB updates, SSE, WebSockets, forms, redirects, debounce, server integration.

---

# htmx Best Practices & Go/Templ Integration

Apply correct htmx patterns when building hypermedia-driven web applications, especially with Go and templ.

## Core Principles

- **Return HTML fragments, not JSON** — htmx is designed for hypermedia; the server returns rendered HTML
- **Use HTML attributes, not JavaScript** — prefer `hx-*` attributes over `htmx.ajax()` or `fetch()` calls
- **Server controls behavior** — use response headers (`HX-Retarget`, `HX-Reswap`, `HX-Redirect`) for control flow
- **Check `HX-Request` header** — return fragments for htmx requests, full pages for normal requests
- **Don't mix paradigms** — avoid using `fetch()` alongside htmx in the same page; pick one approach

---

## Reference Files

Read the relevant file for detailed patterns, code examples, and best practices:

### `templ-integration.md` — Templ + htmx
- CRITICAL: Templ interpolation rules (dynamic attributes, `{ }` vs quoted strings)
- Dynamic JSON in `hx-vals` — use `json.Marshal`, not `fmt.Sprintf`
- URL construction patterns (fmt.Sprintf, concatenation, templ.URL)
- Templ component patterns (spread attributes, conditional attributes, full page vs partial)
- JavaScript and `hx-on` events in templ (JSFuncCall, OnceHandle, event name syntax)
- Embedding Go data in script tags
- Alpine.js listening to htmx events from templ

### `go-handlers.md` — Go Server Patterns
- Fragment vs full page response (`isHTMXRequest` helper)
- Separate routes for partials vs full pages
- Multi-target OOB responses (writing multiple components)
- htmx-aware redirects (`HX-Redirect` instead of HTTP 302)
- Event-driven list reloads with `HX-Trigger` header
- Delete with empty response
- Validation error re-rendering with error state

### `attributes-reference.md` — Swap, Triggers & Headers
- Swap strategies table (innerHTML, outerHTML, delete, morph, etc.) and modifiers
- Trigger patterns (events, special triggers, modifiers, filters, multiple triggers)
- Self-terminating polling pattern
- Request headers (sent automatically) and response headers (server control)
- Out-of-Band (OOB) swap patterns and gotchas

### `patterns-and-extensions.md` — Advanced Patterns
- Error handling (4xx/5xx don't swap by default — 4 solutions)
- Filter state preservation with `hx-include` and `hx-push-url`
- Forms and file uploads (auto-submit, progress, external values, radio/checkbox)
- Inline editing pattern (read-only row ↔ edit form)
- Alpine.js + htmx integration (separation of concerns, event listening, `htmx.process()`)
- Loading indicators and disabled elements
- Sync strategies (`hx-sync`: replace, abort, queue)
- Target selectors (this, closest, next, previous, find)
- Extensions (json-enc, SSE, WebSockets, head-support, preload)
- JavaScript event patterns (delegation, afterSwap vs afterSettle, `htmx.onLoad`)
- Common anti-patterns table
- CSRF protection pattern
- Configuration via meta tag
- Useful Go libraries (htmx-go, go-htmx, typed-htmx-go)
