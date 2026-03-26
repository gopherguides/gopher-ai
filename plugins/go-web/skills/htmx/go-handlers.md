# Go Handler Patterns

## Fragment vs Full Page

```go
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

## Alternative: Separate Routes for Partials

Instead of checking `HX-Request`, use route structure:

```go
e.GET("/items", h.ItemsPage)          // Full page
e.GET("/api/items", h.ItemsPartial)    // htmx partial
```

## Multi-Target Response with OOB (Writing Multiple Components)

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

## htmx-Aware Redirects

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

## Event-Driven List Reloads with HX-Trigger

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

## Delete with Empty Response

```go
// Return empty 200 — htmx removes the element via hx-swap="delete" or hx-swap="outerHTML"
func (h *Handler) DeleteItem(c echo.Context) error {
    // ... delete ...
    return c.NoContent(http.StatusOK)
}
```

## Validation Error Re-rendering

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
