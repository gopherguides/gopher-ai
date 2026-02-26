---
name: htmx
description: |
  WHEN: User is building web apps with htmx, writing hx-* attributes, handling htmx events,
  using htmx with Go templ templates, debugging htmx requests/swaps, or asking about htmx
  patterns including OOB swaps, SSE, WebSockets, extensions, or JavaScript integration
  WHEN NOT: Non-htmx projects, pure client-side SPA frameworks (React/Vue/Svelte)
---

<!-- cache:start -->

# htmx Best Practices & Go/Templ Integration

Apply correct htmx patterns when building hypermedia-driven web applications, especially with Go and templ.

## Core Principles

- **Return HTML fragments, not JSON** — htmx is designed for hypermedia; the server returns rendered HTML
- **Use HTML attributes, not JavaScript** — prefer `hx-*` attributes over `htmx.ajax()` or `fetch()` calls
- **Server controls behavior** — use response headers (`HX-Retarget`, `HX-Reswap`, `HX-Redirect`) for control flow
- **Check `HX-Request` header** — return fragments for htmx requests, full pages for normal requests
- **Don't mix paradigms** — avoid using `fetch()` alongside htmx in the same page; pick one approach

---

## Templ Interpolation Rules (CRITICAL)

Templ does NOT support string interpolation inside quoted attribute values. This is the #1 source of bugs.

### Dynamic Attributes

```go
// CORRECT: Go expression in curly braces (no quotes around braces)
templ ItemLink(id string) {
    <div hx-get={ fmt.Sprintf("/items/%s", id) }>Load</div>
}

// CORRECT: String concatenation also works
templ ItemLink(id string) {
    <div hx-get={ "/items/" + id }>Load</div>
}

// CORRECT: Echo named routes for type-safe URLs
templ ItemLink(c echo.Context, id string) {
    <div hx-get={ c.Echo().Reverse("items-show", id) }>Load</div>
}

// WRONG: No interpolation inside quoted strings — emits literal "{ id }"
templ ItemLink(id string) {
    <div hx-get="/items/{ id }">Load</div>
}
```

### Dynamic JSON in hx-vals — Use json.Marshal, Not fmt.Sprintf

`fmt.Sprintf` with `%s` into JSON is an injection risk if the value contains `"`, `\`, or newlines. Always use `json.Marshal` or `%q` for safety.

```go
// CORRECT: json.Marshal helper (safest — handles all special characters)
func hxVals(data map[string]any) string {
    b, err := json.Marshal(data)
    if err != nil {
        return "{}"
    }
    return string(b)
}

templ ItemButton(item Item) {
    <button hx-post="/api/items" hx-vals={ hxVals(map[string]any{"id": item.ID}) }>
        Save
    </button>
}

// CORRECT: %q for CSRF tokens (Go-safe quoting, handles quotes/backslashes)
templ Layout(c echo.Context, content templ.Component) {
    <body hx-headers={ fmt.Sprintf(`{"X-CSRF-Token": %q}`, CSRFToken(c)) }>
        @content
    </body>
}

// CORRECT: Static JSON uses plain quoted attribute
templ StaticVals() {
    <button hx-post="/api" hx-vals='{"key": "value"}'>Submit</button>
}

// DANGEROUS: %s with unescaped strings — breaks if value contains quotes
// A message like: Missing "alt" attribute → produces broken JSON
templ BrokenVals(message string) {
    <button hx-vals={ fmt.Sprintf(`{"message": "%s"}`, message) }>Send</button>
}

// WRONG: Mixing constant and dynamic syntax — emits literal "{ token }"
templ BrokenVals(token string) {
    <button hx-vals='{"csrf": "{ token }"}'>Submit</button>
}
```

### URL Construction

```go
// CORRECT: fmt.Sprintf for server-constructed URLs with multiple params
templ ItemRow(item Item) {
    <tr hx-get={ fmt.Sprintf("/items/%d/edit", item.ID) } hx-trigger="click"
        hx-target="this" hx-swap="outerHTML">
        <td>{ item.Name }</td>
    </tr>
}

// CORRECT: String concatenation for simple paths
templ JobRow(jobID string) {
    <tr hx-get={ "/api/jobs/" + jobID + "/row" } hx-trigger="every 2s" hx-swap="outerHTML">
        // row content
    </tr>
}

// CORRECT: Query parameters appended to route
templ Pagination(c echo.Context, saID string, limit, offset int) {
    <button hx-get={ c.Echo().Reverse("transactions", saID) +
        fmt.Sprintf("?limit=%d&offset=%d", limit, offset) }>
        Next
    </button>
}

// CORRECT: templ.URL() for user-influenced URLs
templ UserLink(userURL string) {
    <a hx-get={ string(templ.URL(userURL)) }>Profile</a>
}

// IMPORTANT: URL-encode dynamic query param values
templ Search(query string) {
    <button hx-get={ fmt.Sprintf("/search?q=%s", url.QueryEscape(query)) }>Search</button>
}
```

### HTML Escaping is Normal

Templ HTML-escapes all attribute values (`"` becomes `&quot;`). This is **correct behavior** — browsers un-escape it before htmx reads the attribute via the DOM API. Never try to work around this.

---

## Templ Component Patterns

### Spread Attributes for Reusable Components

Use `templ.Attributes` with spread syntax to inject htmx attributes into reusable UI components. This keeps components htmx-agnostic while allowing consumers to add any htmx behavior.

```go
// Component definition — accepts arbitrary attributes via spread
templ Button(text string, attrs templ.Attributes) {
    <button class="btn btn-primary" { attrs... }>{ text }</button>
}

// Consumer injects htmx behavior
@Button("Save", templ.Attributes{
    "hx-post":   "/api/items",
    "hx-target": "#result",
    "hx-swap":   "innerHTML",
})

// Works with templUI-style Props pattern too
@input.Input(input.Props{
    Type:  input.TypeSearch,
    Name:  "search",
    Attributes: templ.Attributes{
        "hx-get":     "/users?partial=true",
        "hx-trigger": "input changed delay:300ms",
        "hx-target":  "#users-table",
    },
})
```

### Conditional Attributes

Use templ `if` blocks inside element tags for conditional htmx behavior:

```go
// Dual-mode form: create vs edit
templ TaskForm(c echo.Context, task *Task) {
    <form
        if task != nil {
            hx-put={ fmt.Sprintf("/tasks/%d", task.ID) }
            hx-target={ fmt.Sprintf("#task-%d", task.ID) }
            hx-swap="outerHTML"
        } else {
            hx-post="/tasks"
            hx-target="#task-list"
            hx-swap="afterbegin"
        }
    >
        // form fields
    </form>
}

// Self-terminating polling (only poll while job is active)
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

// Boolean attributes
templ SubmitButton(isDisabled bool) {
    <button hx-post="/submit" disabled?={ isDisabled }>Submit</button>
}

// selected?= for option elements (cleaner than if blocks)
<option value="low" selected?={ task.Priority == "low" }>Low</option>
```

### Separated Components for Full Page vs Partial

Extract the inner content as a separate component so the same templ renders both as a full page and as an htmx partial:

```go
// Full page (normal request)
templ ProductDetail(c echo.Context, product Product) {
    @layouts.Main(c, product.Name) {
        <div id="product-detail">
            @ProductDetailContent(product)
        </div>
    }
}

// Partial (htmx request) — same inner component
templ ProductDetailContent(product Product) {
    <h1>{ product.Name }</h1>
    // ...
}
```

---

## JavaScript and hx-on Events in Templ

Templ treats `hx-on:*` attributes as script attributes. They expect `templ.JSFuncCall` or constant strings, NOT plain Go string variables.

### Correct Patterns

```go
// CORRECT: Simple constant inline JS
templ SimpleButton() {
    <button hx-get="/items"
        hx-on::after-request="document.getElementById('spinner').classList.add('hidden')">
        Load
    </button>
}

// CORRECT: Conditional form reset on success
templ ContactForm() {
    <form hx-post="/contact"
        hx-on::after-request="if(event.detail.successful) this.reset()">
        // fields
    </form>
}

// CORRECT: templ.JSFuncCall for dynamic data
var confirmHandle = templ.NewOnceHandle()

templ DeleteButton(id string) {
    @confirmHandle.Once() {
        <script>
            function confirmDelete(id, event) {
                if (!confirm("Delete item " + id + "?")) {
                    event.preventDefault();
                }
            }
        </script>
    }
    <button hx-delete={ fmt.Sprintf("/api/items/%s", id) }
        hx-on::before-request={ templ.JSFuncCall("confirmDelete", id) }>
        Delete
    </button>
}

// CORRECT: templ.JSFuncCall for onclick with dynamic args (safely escapes values)
templ CopyButton(text string) {
    <button onclick={ templ.JSFuncCall("copyToClipboard", text) }>
        Copy
    </button>
}

// WRONG: Plain Go string variable for hx-on
templ BrokenHandler(handler string) {
    <button hx-on::click={ handler }>Click</button>
}
```

### Event Name Syntax

```html
<!-- All valid: -->
<button hx-on::before-request="...">        <!-- shorthand (double colon, omits htmx:) -->
<button hx-on:htmx:before-request="...">    <!-- long form -->
<button hx-on--before-request="...">         <!-- dash form (JSX-compatible) -->

<!-- WRONG: camelCase (HTML attributes are case-insensitive) -->
<button hx-on:htmx:beforeRequest="...">
```

### Alpine.js Listening to htmx Events

```go
// Alpine can listen to htmx events with @ syntax
<form hx-put="/tasks/1" hx-target="closest div" hx-swap="outerHTML"
    @htmx:after-request="editing = false">
```

### Embedding Go Data in Script Tags

```go
// {{ }} syntax inside script tags for string values
templ PageScript(endpoint string) {
    <script>
        const endpoint = "{{ endpoint }}";
    </script>
}

// templ.JSONScript for structured data (safest)
templ ItemPage(items []Item) {
    @templ.JSONScript("items-data", items)
    <script>
        const items = JSON.parse(document.getElementById('items-data').textContent);
    </script>
}

// templ.NewOnceHandle() prevents duplicate script tags in repeated components
```

### Dynamic hx-post via JavaScript (When URL Is Unknown Until Interaction)

When the target URL depends on user interaction (e.g., editing different rows in a shared modal), set it dynamically and re-process:

```javascript
const form = document.getElementById('edit-form');
form.setAttribute('hx-post', '/items/' + itemId + '/edit');
htmx.process(form);  // CRITICAL: htmx must re-scan to pick up the new attribute
```

---

## Go Handler Patterns

### Fragment vs Full Page

```go
// Standard pattern with helper function
func isHTMXRequest(r *http.Request) bool {
    return r.Header.Get("HX-Request") == "true"
}

func (h *Handler) ListItems(c echo.Context) error {
    items, err := h.store.ListItems(c.Request().Context())
    if err != nil {
        return err
    }
    if isHTMXRequest(c.Request()) {
        return views.ItemList(items).Render(c.Request().Context(), c.Response().Writer)
    }
    return views.ItemsPage(c, items).Render(c.Request().Context(), c.Response().Writer)
}
```

### Alternative: Separate Routes for Partials

Instead of checking `HX-Request`, use route structure:

```go
e.GET("/items", h.ItemsPage)          // Full page
e.GET("/api/items", h.ItemsPartial)    // htmx partial
```

### Multi-Target Response with OOB (Writing Multiple Components)

```go
func (h *Handler) CreateAPIKey(c echo.Context) error {
    // ... create key ...
    ctx := c.Request().Context()

    // Render primary response first (goes to hx-target)
    if err := views.APIKeysList(c, keys).Render(ctx, c.Response().Writer); err != nil {
        return err
    }
    // Then render OOB component (has hx-swap-oob="true", goes to its own target)
    if err := views.NewKeyModal(c, apiKey).Render(ctx, c.Response().Writer); err != nil {
        return err
    }
    return nil
}
```

### htmx-Aware Redirects

Always check `HX-Request` before redirecting — htmx ignores HTTP 302 redirects:

```go
func Redirect(c echo.Context, url string) error {
    if c.Request().Header.Get("HX-Request") == "true" {
        c.Response().Header().Set("HX-Redirect", url)
        return c.NoContent(http.StatusOK)
    }
    return c.Redirect(http.StatusSeeOther, url)
}
```

### Event-Driven List Reloads with HX-Trigger

Instead of OOB swaps, trigger a client-side refetch after mutations:

```go
// Handler: signal that data changed
func (h *Handler) DeleteItem(c echo.Context) error {
    // ... delete ...
    c.Response().Header().Set("HX-Trigger", "reloadList")
    return c.NoContent(http.StatusOK)
}
```

```go
// Template: list container listens for the event
<div id="items-list"
    hx-get={ c.Echo().Reverse("items-list") }
    hx-trigger="reloadList from:body"
    hx-swap="innerHTML">
    // items here
</div>
```

### Delete with Empty Response

```go
// Return empty 200 — htmx removes the element via hx-swap="delete" or hx-swap="outerHTML"
func (h *Handler) DeleteItem(c echo.Context) error {
    // ... delete ...
    return c.NoContent(http.StatusOK)
}
```

### Validation Error Re-rendering

Store errors in echo context and re-render the same form component:

```go
func (h *Handler) UpdateItem(c echo.Context) error {
    errMap := NewErrMap()
    if name == "" {
        errMap.Add("name", "Name is required")
    }
    if len(errMap) > 0 {
        c.Set("errors", errMap)
        return views.ItemForm(c, item).Render(c.Request().Context(), c.Response().Writer)
    }
    // ... save ...
}
```

```go
// In templ: conditional error display
<input name="name" type="text"
    class={ "border rounded px-3 py-2",
        templ.KV("border-red-300", views.HasErrors(c, "name")),
        templ.KV("border-gray-300", !views.HasErrors(c, "name")) }>
if views.HasErrors(c, "name") {
    <p class="text-red-500 text-sm">{ views.FirstError(c, "name") }</p>
}
```

---

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

The best polling pattern: include `hx-trigger="every Ns"` only when the condition is active. When the server returns a response without the polling attributes, polling stops automatically.

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

## Request/Response Headers

### Request Headers (sent by htmx automatically)

| Header | Value |
|--------|-------|
| `HX-Request` | Always `"true"` — do NOT set this manually via `hx-headers`, it's redundant |
| `HX-Trigger` | ID of triggering element |
| `HX-Trigger-Name` | Name of triggering element |
| `HX-Target` | ID of target element |
| `HX-Current-URL` | Browser's current URL |
| `HX-Boosted` | `"true"` if boosted |

### Response Headers (server sends to control htmx)

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
// Go handler writes multiple components — primary first, then OOB
templ PrimaryResponse(task Task) {
    @TaskItem(task)
}

templ StatsOOB(stats Stats) {
    <div id="task-count" hx-swap-oob="true">
        { fmt.Sprint(stats.Total) } tasks
    </div>
}

// Tab state OOB update (update active tab styling alongside content)
templ FilterTabsOOB(activeFilter string) {
    <div id="filter-tabs" hx-swap-oob="outerHTML:#filter-tabs">
        // tabs with active styling
    </div>
}

// Style card OOB (two-panel sync — update sidebar card when detail panel changes)
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

---

## Error Handling

### 4xx/5xx Responses Don't Swap by Default

This is a major gotcha. Form validation returning 422 won't display errors unless configured.

**Option 1: Re-render form at 200 with error state** (most common in Go/templ)

The server returns HTTP 200 with the form re-rendered showing inline errors. This avoids the 4xx swap problem entirely.

**Option 2: response-targets extension**

```html
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-response-targets@2.0.4"></script>
<div hx-ext="response-targets">
    <form hx-post="/register"
        hx-target="#success"
        hx-target-422="#validation-errors"
        hx-target-5*="#server-error">
    </form>
</div>
```

**Option 3: HX-Retarget response header**

```go
if c.Request().Header.Get("HX-Request") == "true" {
    c.Response().Header().Set("HX-Retarget", "#error-container")
    return views.ErrorAlert(message).Render(c.Request().Context(), c.Response().Writer)
}
```

**Option 4: beforeSwap event**

```javascript
document.body.addEventListener('htmx:beforeSwap', function(event) {
    if (event.detail.xhr.status === 422) {
        event.detail.shouldSwap = true;
        event.detail.isError = false;
    }
});
```

---

## Filter State Preservation

When building filter/search UIs, use `hx-include` to carry all filter values and `hx-push-url` for bookmarkable URLs:

```go
templ ProductFilters(sortBy, sortDir, brand, category string) {
    // Hidden inputs carry state across filter changes
    <input type="hidden" name="sort" value={ sortBy }/>
    <input type="hidden" name="dir" value={ sortDir }/>
    <input type="hidden" name="category" value={ category }/>

    <select name="brand"
        hx-get="/products"
        hx-trigger="change"
        hx-target="#products-table"
        hx-include="[name='q'],[name='sort'],[name='dir'],[name='category']"
        hx-push-url="true">
        // options
    </select>

    <input type="search" name="q"
        hx-get="/products"
        hx-trigger="input changed delay:300ms, search"
        hx-target="#products-table"
        hx-include="[name='brand'],[name='sort'],[name='dir'],[name='category']"
        hx-push-url="true">
}
```

---

## Forms and File Uploads

### File Upload with Auto-Submit on Selection

```go
// Hidden file input triggered by a styled button — uploads immediately on selection
<input type="file" accept="image/*" multiple
    class="hidden"
    x-ref="fileInput"
    hx-post={ fmt.Sprintf("/items/%s/images", item.ID) }
    hx-trigger="change"
    hx-target="#images-section"
    hx-swap="innerHTML"
    hx-encoding="multipart/form-data"
    name="images"/>
<button @click="$refs.fileInput.click()">Upload Images</button>
```

### File Upload with Progress and Disabled Submit

```html
<form hx-post="/upload" hx-encoding="multipart/form-data"
    hx-indicator="#upload-spinner" hx-disabled-elt="button[type=submit]">
    <input type="file" name="document">
    <button type="submit">
        <span>Upload</span>
        <span id="upload-spinner" class="htmx-indicator">Uploading...</span>
    </button>
</form>
```

### Include External Values

```html
<!-- Pull in values from outside the form -->
<input id="global-filter" name="filter" value="active">
<form hx-post="/search" hx-include="#global-filter">
    <input name="query" type="text">
    <button type="submit">Search</button>
</form>

<!-- Include a subset of a larger form -->
<button hx-post="/items/add-color" hx-encoding="multipart/form-data"
    hx-include="#add-color-form">Add Color</button>
```

### Radio/Checkbox Auto-Submit

```go
// Radio buttons that auto-submit on change (default trigger for inputs)
<input type="radio" name={ fmt.Sprintf("primary-image-%s", productID) }
    value={ img.ID }
    checked?={ img.IsPrimary }
    hx-put={ fmt.Sprintf("/images/%s/set-primary", img.ID) }
    hx-target="#images-grid"
    hx-swap="outerHTML"
    hx-indicator="none">
```

---

## Inline Editing Pattern

The most common htmx pattern in Go/templ apps:

```go
// Read-only row
templ EntryRow(entry Entry) {
    <tr id={ fmt.Sprintf("entry-%d", entry.ID) }>
        <td>{ entry.Name }</td>
        <td>
            <button hx-get={ fmt.Sprintf("/entries/%d/edit", entry.ID) }
                hx-target={ fmt.Sprintf("#entry-%d", entry.ID) }
                hx-swap="outerHTML">Edit</button>
            <button hx-delete={ fmt.Sprintf("/entries/%d", entry.ID) }
                hx-target={ fmt.Sprintf("#entry-%d", entry.ID) }
                hx-swap="delete"
                hx-confirm="Are you sure?">Delete</button>
        </td>
    </tr>
}

// Edit form (replaces the row)
templ EntryEditForm(entry Entry) {
    <tr id={ fmt.Sprintf("entry-%d", entry.ID) }>
        <td><input name="name" value={ entry.Name } form={ fmt.Sprintf("edit-form-%d", entry.ID) }></td>
        <td>
            <form id={ fmt.Sprintf("edit-form-%d", entry.ID) }
                hx-put={ fmt.Sprintf("/entries/%d", entry.ID) }
                hx-target={ fmt.Sprintf("#entry-%d", entry.ID) }
                hx-swap="outerHTML">
                <button type="submit">Save</button>
            </form>
            <button hx-get={ fmt.Sprintf("/entries/%d", entry.ID) }
                hx-target={ fmt.Sprintf("#entry-%d", entry.ID) }
                hx-swap="outerHTML">Cancel</button>
        </td>
    </tr>
}
```

---

## Alpine.js + htmx Integration

### Separation of Concerns

Use htmx for server communication, Alpine for client-side UI state:

```go
// Alpine dropdown + htmx server action
<div x-data="{ open: false }">
    <button @click="open = !open">Actions</button>
    <div x-show="open" @click.away="open = false" x-transition>
        <button hx-post={ "/api/scrape/" + brand }
            hx-swap="none"
            @click="open = false">
            Full Scrape
        </button>
    </div>
</div>
```

### Alpine Reacting to htmx Events

```go
// Alpine state updates based on htmx lifecycle
<div x-data="{ loading: false }"
    @htmx:before-request.window="loading = true"
    @htmx:after-request.window="loading = false">
    <div x-show="loading">Loading...</div>
</div>
```

### Dynamic Alpine-bound htmx Attributes

When Alpine dynamically sets `hx-*` attributes, htmx doesn't see them because it scanned at page load. Call `htmx.process()` to re-scan:

```html
<button :hx-post="'/api/favorites/' + productId"
    hx-swap="outerHTML"
    x-init="htmx.process($el)">
```

---

## Loading Indicators

```html
<!-- Built-in indicator pattern -->
<button hx-get="/api" hx-indicator="#spinner">Load</button>
<span id="spinner" class="htmx-indicator">Loading...</span>

<!-- CSS for show/hide indicators -->
<style>
.htmx-indicator { display: none; }
.htmx-request .htmx-indicator { display: inline-flex; }
.htmx-request.htmx-indicator { display: inline-flex; }
.htmx-indicator-hide { }
.htmx-request .htmx-indicator-hide { display: none; }
</style>

<!-- Toggle text during request -->
<button hx-post="/save" hx-indicator="this">
    <span class="htmx-indicator-hide">Save</span>
    <span class="htmx-indicator">Saving...</span>
</button>

<!-- Disable button during request -->
<button hx-post="/save" hx-disabled-elt="this">Save</button>

<!-- Disable all form controls -->
<form hx-post="/submit" hx-disabled-elt="find input, find button">
```

---

## htmx Sync Strategies

Prevent request conflicts with `hx-sync`:

```html
<!-- Replace in-flight request with new one (best for search inputs) -->
<input hx-get="/search" hx-trigger="input changed delay:300ms" hx-sync="this:replace">

<!-- Abort in-flight request, send new one -->
<button hx-get="/api" hx-sync="this:abort">Load</button>

<!-- Queue requests, keep only the last -->
<button hx-get="/api" hx-sync="this:queue last">Load</button>

<!-- Sync with a different element (abort validation on form submit) -->
<form hx-post="/submit">
    <input hx-get="/validate" hx-sync="closest form:abort">
    <button type="submit">Submit</button>
</form>
```

---

## Target Selectors

Extended CSS selectors for `hx-target`:

```html
<button hx-get="/api" hx-target="this">                  <!-- The element itself -->
<button hx-get="/api" hx-target="closest div">            <!-- Nearest ancestor div -->
<button hx-get="/api" hx-target="closest tr">             <!-- Nearest table row -->
<button hx-get="/api" hx-target="next .result">           <!-- Next sibling matching -->
<button hx-get="/api" hx-target="previous .result">       <!-- Previous sibling matching -->
<button hx-get="/api" hx-target="find .child">            <!-- Descendant matching -->
<button hx-get="/api" hx-target="#specific-id">            <!-- Standard CSS selector -->
```

---

## Common Extensions

### json-enc — Send JSON Bodies

```html
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-json-enc@2.0.1"></script>
<form hx-post="/api/users" hx-ext="json-enc">
    <input name="name" value="John">
    <button type="submit">Create</button>
</form>
```

### SSE — Server-Sent Events

```html
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-sse@2.2.4"></script>
<div hx-ext="sse" sse-connect="/events" sse-swap="message">Waiting...</div>

<!-- SSE triggers a separate HTTP request -->
<div hx-ext="sse" sse-connect="/events">
    <div hx-get="/latest" hx-trigger="sse:data-changed">Loads on SSE event</div>
</div>
```

### WebSockets

```html
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-ws@2.0.4"></script>
<div hx-ext="ws" ws-connect="/chat">
    <div id="messages"></div>
    <form ws-send>
        <input name="message" type="text">
        <button type="submit">Send</button>
    </form>
</div>
```

### head-support, preload, loading-states

```html
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-head-support@2.0.3"></script>
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-preload@2.1.0"></script>
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-loading-states@2.0.0"></script>
```

---

## JavaScript Event Patterns

### Event Delegation (Required for Swapped Content)

```javascript
// CORRECT: Listen on body or a stable parent — catches events from dynamically swapped content
document.body.addEventListener('htmx:afterSwap', function(event) {
    if (event.detail.elt.id === 'my-form') { /* ... */ }
});

// CORRECT: htmx helper
htmx.on('htmx:afterSwap', function(event) { /* ... */ });

// WRONG: Direct listener on element that may be swapped out
document.querySelector('#my-button').addEventListener('htmx:afterSwap', fn);
```

### afterSwap vs afterSettle Timing

```javascript
// afterSwap: Content in DOM but transitions NOT started — don't init JS libraries here
// afterSettle: DOM fully settled, transitions started — safe for initialization

// BEST: Use htmx.onLoad for initializing JS on new content
htmx.onLoad(function(content) {
    initializeTooltips(content);
    initializeCharts(content);
});
```

### Programmatic Search Clear

```javascript
// Clear search and re-trigger htmx request
document.getElementById('search').value = '';
htmx.trigger(document.getElementById('search'), 'keyup');
```

---

## Common Anti-Patterns

| Anti-Pattern | Why It's Wrong | Correct Approach |
|---|---|---|
| `hx-vals={ fmt.Sprintf(\`{"msg": "%s"}\`, userInput) }` | JSON injection if value has `"` or `\` | Use `json.Marshal` helper or `%q` |
| `hx-swap="none"` + `window.location.reload()` | Defeats htmx purpose entirely | Return HTML fragment and swap, or use `HX-Redirect` |
| `hx-swap="none"` with no feedback | User clicks, nothing visible happens | Add `hx-indicator`, return content, or use `HX-Trigger` for list reload |
| `hx-target="body"` for navigation-like actions | Loses all client state, scroll position | Use `<a href>` links or `HX-Redirect` |
| `hx-headers='{"HX-Request": "true"}'` on body | htmx already sets this header automatically | Remove — it's redundant |
| `hx-post` on both `<form>` AND `<button>` | Button's attributes override form's target/swap | Put `hx-post` on the form OR the button, not both |
| Duplicate IDs (e.g., wrapper and loader both `id="items"`) | `hx-target` matches the first one, undefined behavior | Use unique IDs |
| Loading htmx as async/defer/module | Unreliable initialization | Use standard blocking `<script>` tag |
| Loading different htmx versions on the same page | Undefined behavior, version conflicts | Use one version in the base layout only |
| Expecting 4xx/5xx to swap content | They don't by default | Re-render at 200 with errors, or use response-targets |
| Not checking `HX-Request` for redirects | HTTP 302 is ignored by htmx | Use `HX-Redirect` header for htmx requests |
| GET requests expecting form values | GET doesn't include enclosing form data | Use `hx-include="closest form"` for GET |
| Using `fetch()` alongside htmx in the same page | Inconsistent patterns, harder to maintain | Pick one approach per page/feature |
| Mixing `htmx.ajax()` and `hx-*` attributes | Confusing dual paradigms | Prefer attributes; use `htmx.ajax()` only when attributes can't work |
| Not URL-encoding dynamic query params | `search=foo&bar=baz` breaks URLs | Use `url.QueryEscape()` for user-supplied values |

---

## CSRF Protection Pattern (Go + Templ)

```go
// Set CSRF token on body so ALL htmx requests include it via attribute inheritance
// Use %q (not %s) to safely handle special characters in the token
templ Layout(c echo.Context, content templ.Component) {
    <html>
    <body hx-headers={ fmt.Sprintf(`{"X-CSRF-Token": %q}`, CSRFToken(c)) }>
        @content
    </body>
    </html>
}
```

---

## Configuration

```html
<!-- Via meta tag (before htmx script) -->
<meta name="htmx-config" content='{
    "defaultSwapStyle": "outerHTML",
    "selfRequestsOnly": true,
    "historyCacheSize": 10,
    "timeout": 5000,
    "globalViewTransitions": false,
    "scrollBehavior": "instant"
}'>
```

Key settings:
- `defaultSwapStyle` (default: `innerHTML`) — change if you prefer `outerHTML`
- `selfRequestsOnly` (default: `true`) — only allow requests to same domain
- `historyCacheSize` (default: `10`) — pages cached for history
- `allowScriptTags` (default: `true`) — execute scripts in swapped content
- `disableInheritance` (default: `false`) — disable attribute inheritance from parents
- `timeout` (default: `0`) — request timeout in ms

### Debug Logging (Conditional)

```go
if config.GetHtmxLogging(c) {
    <script>htmx.logAll();</script>
}
```

---

## Useful Go Libraries

- **`github.com/angelofallars/htmx-go`** — Type-safe htmx response headers and request detection
- **`github.com/donseba/go-htmx`** — Seamless htmx integration with partial render support
- **`github.com/will-wow/typed-htmx-go`** — Type-safe htmx attributes for templ with autocomplete

<!-- cache:end -->
