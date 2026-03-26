# Templ Integration with htmx

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
