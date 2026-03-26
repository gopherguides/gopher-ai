# Patterns, Extensions & Advanced Usage

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
<button hx-get="/api" hx-indicator="#spinner">Load</button>
<span id="spinner" class="htmx-indicator">Loading...</span>

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
// CORRECT: Listen on body or a stable parent
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
// afterSwap: Content in DOM but transitions NOT started
// afterSettle: DOM fully settled, transitions started — safe for initialization

// BEST: Use htmx.onLoad for initializing JS on new content
htmx.onLoad(function(content) {
    initializeTooltips(content);
    initializeCharts(content);
});
```

### Programmatic Search Clear

```javascript
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
