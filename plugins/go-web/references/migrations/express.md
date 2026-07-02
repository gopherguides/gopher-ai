# Express.js to Echo Migration

Loaded on demand by /go-web:convert-to-go-project when the source project uses Express.js (or similar Node HTTP frameworks).

**Route Mapping:**

```javascript
// Express (before)
router.get('/users', usersController.list);
router.post('/users', usersController.create);
router.get('/users/:id', usersController.show);
router.put('/users/:id', usersController.update);
router.delete('/users/:id', usersController.delete);
```

```go
// Echo (after)
e.GET("/users", h.UserList)
e.POST("/users", h.UserCreate)
e.GET("/users/:id", h.UserShow)
e.PUT("/users/:id", h.UserUpdate)
e.DELETE("/users/:id", h.UserDelete)
```

**Middleware Conversion:**

```javascript
// Express middleware
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));
```

```go
// Echo middleware
e.Use(middleware.CORS())
e.Use(middleware.Logger())
e.Use(middleware.Recover())
```

**Controller to Handler:**

```javascript
// Express controller
exports.list = async (req, res) => {
  const users = await User.findAll();
  res.json(users);
};
```

```go
// Go handler
func (h *Handler) UserList(c echo.Context) error {
    ctx := c.Request().Context()
    users, err := h.db.Queries.ListUsers(ctx)
    if err != nil {
        return err
    }
    return c.JSON(http.StatusOK, users)
}
```

## Meta/SEO Migration (Express)

**From Express (res.render with vars):**

```javascript
// Express (before)
res.render('page', { title: 'My Page' });
```

```go
// Go handler (after) - clean, no meta
func (h *Handler) Page(c echo.Context) error {
    return pages.Page().Render(c.Request().Context(), c.Response().Writer)
}
```
