# Next.js to Go + HTMX Migration

Loaded on demand by /go-web:convert-to-go-project when the source project uses Next.js or a React SPA.

**API Routes:**

```javascript
// Next.js API route (pages/api/users.js)
export default async function handler(req, res) {
  if (req.method === 'GET') {
    const users = await prisma.user.findMany();
    res.json(users);
  }
}
```

```go
// Go handler
func (h *Handler) UserList(c echo.Context) error {
    users, err := h.db.Queries.ListUsers(c.Request().Context())
    if err != nil {
        return err
    }
    return c.JSON(http.StatusOK, users)
}
```

**React Component to Templ + HTMX:**

```jsx
// React with fetch
function UserList() {
  const [users, setUsers] = useState([]);
  useEffect(() => {
    fetch('/api/users').then(r => r.json()).then(setUsers);
  }, []);
  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

```templ
// Templ with HTMX
templ UserList(users []User) {
    <ul hx-get="/users" hx-trigger="load" hx-swap="innerHTML">
        for _, user := range users {
            <li>{ user.Name }</li>
        }
    </ul>
}
```

## Meta/SEO Migration (Next.js)

**From Next.js (handler passes meta):**

```jsx
// Next.js (before)
export const metadata = {
  title: 'My Page',
  description: 'Page description',
};
```

```templ
// Go template (after) - template constructs meta
templ MyPage() {
    @layouts.Base(meta.New("My Page", "Page description")) {
        // content
    }
}
```
