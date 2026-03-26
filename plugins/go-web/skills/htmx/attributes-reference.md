# Swap Strategies, Triggers & Headers Reference

## Swap Strategies

| Strategy | Behavior | When to Use |
|----------|----------|-------------|
| `innerHTML` | Replace inner content (default) | Update container contents |
| `outerHTML` | Replace entire element | Replace a component entirely, inline edit |
| `textContent` | Replace text only, no HTML parsing | Display raw text safely |
| `beforebegin` | Insert before target | Add sibling before element |
| `afterbegin` | Prepend inside target | Prepend to a list (new items first) |
| `beforeend` | Append inside target | Append to a list (infinite scroll) |
| `afterend` | Insert after target | Add sibling after element |
| `delete` | Remove target element | Delete items from lists |
| `none` | No swap (OOB still processed) | Side-effect-only requests, HX-Redirect |
| `morph` | Idiomorph morphing (extension) | Preserve state/focus during updates |

### Swap Modifiers

Append to `hx-swap` value: `hx-swap="innerHTML swap:500ms settle:100ms scroll:top transition:true focus-scroll:true ignoreTitle:true"`

---

## Trigger Patterns

```html
<!-- Standard events -->
<button hx-get="/api" hx-trigger="click">Click</button>
<input hx-get="/search" hx-trigger="input changed delay:500ms" hx-target="#results">
<form hx-post="/submit" hx-trigger="submit">

<!-- Special triggers -->
<div hx-get="/content" hx-trigger="load">                  <!-- On page load -->
<div hx-get="/content" hx-trigger="revealed">               <!-- When scrolled into view -->
<div hx-get="/content" hx-trigger="intersect threshold:0.5"> <!-- Intersection observer -->
<div hx-get="/poll" hx-trigger="every 2s">                  <!-- Polling -->

<!-- Modifiers -->
<button hx-get="/api" hx-trigger="click once">              <!-- Fire once only -->
<input hx-get="/validate" hx-trigger="input changed delay:300ms"> <!-- Debounce -->
<input hx-get="/search" hx-trigger="keyup changed delay:500ms, search"> <!-- Debounce + clear button -->
<input hx-get="/search" hx-trigger="keyup throttle:500ms">  <!-- Throttle -->
<button hx-get="/api" hx-trigger="click from:body">         <!-- Listen on different element -->
<button hx-get="/api" hx-trigger="click consume">           <!-- Stop propagation -->
<button hx-get="/api" hx-trigger="click queue:last">        <!-- Queue strategy -->

<!-- Event filters (JS boolean expressions) -->
<button hx-get="/api" hx-trigger="click[ctrlKey]">          <!-- Only with Ctrl held -->
<input hx-get="/api" hx-trigger="keyup[key=='Enter']">      <!-- Only on Enter key -->

<!-- Multiple triggers -->
<div hx-get="/api" hx-trigger="click, keyup[key=='Enter'] from:body">

<!-- Event-driven trigger (from HX-Trigger response header) -->
<div hx-get="/items" hx-trigger="reloadList from:body" hx-swap="innerHTML">
```

### Self-Terminating Polling

Include `hx-trigger="every Ns"` only when the condition is active. When the server returns a response without the polling attributes, polling stops automatically.

```go
templ JobRow(job Job) {
    if job.Status == "running" || job.Status == "pending" {
        <tr id={ "job-" + job.ID }
            hx-get={ "/api/jobs/" + job.ID + "/row" }
            hx-trigger="every 2s"
            hx-swap="outerHTML">
            @jobRowContent(job)
        </tr>
    } else {
        <tr id={ "job-" + job.ID }>
            @jobRowContent(job)
        </tr>
    }
}
```

---

## Request Headers (sent by htmx automatically)

| Header | Value |
|--------|-------|
| `HX-Request` | Always `"true"` — do NOT set this manually via `hx-headers`, it's redundant |
| `HX-Trigger` | ID of triggering element |
| `HX-Trigger-Name` | Name of triggering element |
| `HX-Target` | ID of target element |
| `HX-Current-URL` | Browser's current URL |
| `HX-Boosted` | `"true"` if boosted |

## Response Headers (server sends to control htmx)

| Header | Effect |
|--------|--------|
| `HX-Location` | Client-side redirect without full page reload |
| `HX-Push-Url` | Push URL into browser history |
| `HX-Redirect` | Full page redirect (use instead of HTTP 302 for htmx) |
| `HX-Refresh` | Full page refresh if `"true"` |
| `HX-Replace-Url` | Replace current URL in history |
| `HX-Reswap` | Override swap strategy |
| `HX-Retarget` | Override target element (CSS selector) |
| `HX-Trigger` | Trigger client-side events (JSON for multiple) |
| `HX-Trigger-After-Swap` | Trigger events after swap |
| `HX-Trigger-After-Settle` | Trigger events after settle |

---

## Out-of-Band (OOB) Swaps

Update multiple parts of the page from a single response:

```go
templ PrimaryResponse(task Task) {
    @TaskItem(task)
}

templ StatsOOB(stats Stats) {
    <div id="task-count" hx-swap-oob="true">
        { fmt.Sprint(stats.Total) } tasks
    </div>
}

templ FilterTabsOOB(activeFilter string) {
    <div id="filter-tabs" hx-swap-oob="outerHTML:#filter-tabs">
        // tabs with active styling
    </div>
}

templ StyleCardOOB(data StyleCardData) {
    <div id={ fmt.Sprintf("style-card-%s", data.StyleID) } hx-swap-oob="true"
        class="border-emerald-500 bg-emerald-500/10">
        // card content
    </div>
}
```

### OOB Gotchas

- OOB elements **must have matching IDs** on the page
- Primary content must come first in the response
- Table elements (`<tr>`, `<td>`) need `<template>` wrappers for OOB
- If OOB target is inside the primary swap area, it may not exist when OOB runs
- Sending only OOB content with no primary response replaces the target with nothing
- Nested OOB is processed by default; disable with `htmx.config.allowNestedOobSwaps = false`
