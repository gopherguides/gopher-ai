# CRITICAL: Templ Interpolation in JavaScript

**Go expressions `{ value }` do NOT interpolate inside `<script>` tags or inline event handlers.** They are treated as literal text, causing errors like:

```
GET http://localhost:8008/app/quotes/%7B%20id.String()%20%7D 400 (Bad Request)
```

The `%7B` and `%7D` are URL-encoded `{` and `}` - proof the expression wasn't evaluated.

## Pattern 1: Data Attributes (Recommended)

Use `data-*` attributes to pass Go values, then access via JavaScript:

```templ
<button
  data-quote-id={ quote.ID.String() }
  onclick="openPublishModal(this.dataset.quoteId)">
  Publish
</button>
```

For multiple values:
```templ
<div
  data-id={ item.ID.String() }
  data-name={ item.Name }
  data-status={ item.Status }
  onclick="handleClick(this.dataset)">
```

## Pattern 2: templ.JSFuncCall (for onclick handlers)

Automatically JSON-encodes arguments and prevents XSS:

```templ
<button onclick={ templ.JSFuncCall("openPublishModal", quote.ID.String()) }>
  Publish
</button>
```

With multiple arguments:
```templ
<button onclick={ templ.JSFuncCall("updateItem", item.ID.String(), item.Name, item.Active) }>
```

To pass the event object, use `templ.JSExpression`:
```templ
<button onclick={ templ.JSFuncCall("handleClick", templ.JSExpression("event"), quote.ID.String()) }>
```

## Pattern 3: Double-Braces Inside Script Strings

Inside `<script>` tags, use `{{ value }}` (double braces) for interpolation:

```templ
<script>
  const quoteId = "{{ quote.ID.String() }}";
  const itemName = "{{ item.Name }}";
  openPublishModal(quoteId);
</script>
```

Outside strings (bare expressions), values are JSON-encoded:
```templ
<script>
  const config = {{ templ.JSONString(config) }};
  const isActive = {{ item.Active }};  // outputs: true or false
</script>
```

## Pattern 4: templ.JSONString for Complex Data

Pass complex structs/maps to JavaScript via attributes:

```templ
<div data-config={ templ.JSONString(config) }>

<script>
  const el = document.querySelector('[data-config]');
  const config = JSON.parse(el.dataset.config);
</script>
```

Or use `templ.JSONScript`:
```templ
@templ.JSONScript("config-data", config)

<script>
  const config = JSON.parse(document.getElementById('config-data').textContent);
</script>
```

## Pattern 5: templ.OnceHandle for Reusable Scripts

Ensures scripts are only rendered once, even when component is used multiple times:

```templ
var publishHandle = templ.NewOnceHandle()

templ QuoteRow(quote Quote) {
  @publishHandle.Once() {
    <script>
      function openPublishModal(id) {
        fetch(`/api/quotes/${id}/publish`, { method: 'POST' });
      }
    </script>
  }
  <button
    data-id={ quote.ID.String() }
    onclick="openPublishModal(this.dataset.id)">
    Publish
  </button>
}
```

## When to Use Each Pattern

| Scenario | Use |
|----------|-----|
| Simple onclick with one value | Data attribute or `templ.JSFuncCall` |
| Multiple values needed in JS | Data attributes |
| Need event object | `templ.JSFuncCall` with `templ.JSExpression("event")` |
| Inline script with Go values | `{{ value }}` double braces |
| Complex object/struct | `templ.JSONString` or `templ.JSONScript` |
| Reusable script in loop | `templ.OnceHandle` |

## Common Mistakes

```templ
// WRONG - won't interpolate, becomes literal text
onclick="doThing({ id })"

// WRONG - single braces don't work in scripts
<script>const x = { value };</script>

// WRONG - Go expression in URL string inside script
<script>
  fetch(`/api/quotes/{ id }/publish`)  // BROKEN
</script>

// CORRECT alternatives:
onclick={ templ.JSFuncCall("doThing", id) }

<script>const x = "{{ value }}";</script>

<button data-id={ id } onclick="doFetch(this.dataset.id)">
```
