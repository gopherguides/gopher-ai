# HTMX + Alpine.js Integration (when using Alpine alongside templUI)

**templUI itself does not use Alpine.js** — its components are vanilla JS via Script() templates (per templui.io: "Zero JS frameworks"). This document covers the **separate, optional** decision to use Alpine.js as a client-side state layer **alongside** templUI in your app.

If you don't need Alpine for app-level state, skip this file — templUI + HTMX + Script() is enough for most apps.

If you've decided to add Alpine, the patterns below show how it composes with HTMX (and indirectly with templUI components since they share the DOM).

## When to Use Each

HTMX and Alpine.js work well together when both are needed. Use HTMX for server communication, Alpine for client-side enhancements.

## When to Use Each

```html
<!-- HTMX: Server-driven (fetches HTML from server) -->
<button hx-get="/api/users" hx-target="#user-list">Load Users</button>

<!-- Alpine: Client-side state (no server call) -->
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open">Content</div>
</div>

<!-- Combined: HTMX loads data, Alpine filters it -->
<div x-data="{ filter: '' }">
  <input x-model="filter" placeholder="Filter...">
  <div hx-get="/users" hx-trigger="load">
    <template x-for="user in users.filter(u => u.name.includes(filter))">
      <div x-text="user.name"></div>
    </template>
  </div>
</div>
```

## Key Integration Patterns

**Alpine-Morph Extension**: Preserves Alpine state across HTMX swaps:
```html
<script src="https://unpkg.com/htmx.org/dist/ext/alpine-morph.js"></script>
<div hx-ext="alpine-morph" hx-swap="morph">...</div>
```

**htmx.process() for Alpine Conditionals**: When Alpine's `x-if` renders HTMX content:
```html
<template x-if="showForm">
  <form hx-post="/submit" x-init="htmx.process($el)">...</form>
</template>
```

**Triggering HTMX from Alpine**:
```html
<button @click="htmx.trigger($refs.form, 'submit')">Submit</button>
```
