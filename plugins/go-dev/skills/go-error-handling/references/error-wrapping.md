# Error Wrapping in Go

## Overview

Error wrapping adds context to errors as they propagate up the call stack. Go provides two wrapping verbs in `fmt.Errorf`: `%w` (preserves the chain) and `%v` (opaque, hides the chain). The `errors` package provides `errors.Is`, `errors.As`, and `errors.Join` for inspecting and combining errors.

## fmt.Errorf with %w (Wrapping)

The `%w` verb wraps an error, creating a chain that `errors.Is` and `errors.As` can traverse:

```go
func ReadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("reading config %s: %w", path, err)
    }
    return parseConfig(data)
}
```

The resulting error chain looks like:

```
"reading config /etc/app.yaml: open /etc/app.yaml: no such file or directory"
    └── *fs.PathError{Op: "open", Path: "/etc/app.yaml", Err: syscall.ENOENT}
        └── syscall.ENOENT
```

Callers can check any error in the chain:

```go
errors.Is(err, fs.ErrNotExist) // true -- traverses the full chain
```

### When to Use %w

Use `%w` for all internal error propagation within your module. This gives callers maximum flexibility to inspect error causes:

```go
func (s *UserService) Create(ctx context.Context, u User) error {
    if err := s.validate(u); err != nil {
        return fmt.Errorf("validating user: %w", err)
    }
    if err := s.repo.Insert(ctx, u); err != nil {
        return fmt.Errorf("inserting user: %w", err)
    }
    return nil
}
```

### Multiple %w in a Single fmt.Errorf (Go 1.20+)

Go 1.20 added support for multiple `%w` verbs in a single `fmt.Errorf` call:

```go
return fmt.Errorf("operation failed: %w, cleanup also failed: %w", opErr, cleanupErr)
```

This creates a multi-error that `errors.Is` and `errors.As` check against both wrapped errors. However, prefer `errors.Join` for combining independent errors -- it produces a cleaner result.

## fmt.Errorf with %v (Opaque)

The `%v` verb includes the error text but does NOT preserve the chain. The original error cannot be found with `errors.Is` or `errors.As`:

```go
func (s *PublicAPI) GetUser(ctx context.Context, id string) (*User, error) {
    u, err := s.userService.Find(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("user lookup failed: %v", err)
    }
    return u, nil
}
```

### When to Use %v

Use `%v` at system boundaries where you do not want callers depending on internal error types:

- **Public API surfaces** -- External consumers should not depend on your internal error types. Wrapping with `%w` creates a coupling contract.
- **Service boundaries** -- When an error crosses from one service layer to another (e.g., repository errors reaching HTTP handlers), `%v` prevents the handler from depending on database-specific errors.
- **Third-party library boundaries** -- When wrapping errors from external libraries that might change their error types between versions.

```go
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    u, err := h.service.Find(r.Context(), chi.URLParam(r, "id"))
    if err != nil {
        // %v at the HTTP boundary -- callers cannot use errors.Is on internal errors
        slog.Error("user lookup failed", slog.Any("error", err))
        http.Error(w, "internal server error", http.StatusInternalServerError)
        return
    }
    // ...
}
```

### Decision: %w vs %v

| Context | Verb | Reason |
|---------|------|--------|
| Within a package | `%w` | Same package, full visibility |
| Between internal packages | `%w` | Same module, controlled coupling |
| Public API return | `%v` | External callers should not depend on internals |
| HTTP handler → response | Neither | Translate to HTTP status, log original error |
| Third-party library error | `%v` or `%w` | `%v` if library is unstable, `%w` if error types are documented |

## errors.Is

`errors.Is` reports whether any error in the chain matches a target value. It replaces direct `==` comparison:

```go
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}
```

### How errors.Is Traverses the Chain

Starting from the outermost error, `errors.Is` calls `Unwrap()` at each level:

```
fmt.Errorf("querying user: %w", sql.ErrNoRows)
│
├── Is(sql.ErrNoRows)? YES → match found
```

For multi-errors (errors implementing `Unwrap() []error`), `errors.Is` checks every branch:

```
errors.Join(err1, err2)
│
├── Is(target) on err1
└── Is(target) on err2
```

### Custom Is Method

Types can override matching behavior by implementing an `Is` method:

```go
type AppError struct {
    Code    int
    Message string
}

func (e *AppError) Is(target error) bool {
    t, ok := target.(*AppError)
    if !ok {
        return false
    }
    return e.Code == t.Code
}
```

This makes `errors.Is` match by code rather than by identity:

```go
err := &AppError{Code: 404, Message: "user not found"}
target := &AppError{Code: 404, Message: ""}
errors.Is(err, target) // true -- matches on Code
```

## errors.As

`errors.As` extracts the first error in the chain that matches a target type:

```go
var pathErr *fs.PathError
if errors.As(err, &pathErr) {
    slog.Error("file operation failed",
        slog.String("op", pathErr.Op),
        slog.String("path", pathErr.Path),
    )
}
```

### Target Must Be a Pointer

The target argument to `errors.As` must be a pointer to the type you want to extract. For error types implemented with pointer receivers, the target is a pointer-to-pointer:

```go
var vErr *ValidationError   // *ValidationError is the error type
errors.As(err, &vErr)       // &vErr is **ValidationError
```

### Custom As Method

Types can override extraction by implementing an `As` method:

```go
func (e *AppError) As(target any) bool {
    t, ok := target.(**AppError)
    if !ok {
        return false
    }
    *t = e
    return true
}
```

### errors.As vs Type Assertion

Never use type assertions on errors. They do not traverse the chain:

```go
// WRONG -- does not check wrapped errors
if pathErr, ok := err.(*fs.PathError); ok {
    // This misses any PathError wrapped inside another error
}

// CORRECT -- traverses the full chain
var pathErr *fs.PathError
if errors.As(err, &pathErr) {
    // Found it, regardless of how deeply wrapped
}
```

## errors.Join (Go 1.20+)

`errors.Join` combines multiple independent errors into a single error:

```go
func validateUser(u User) error {
    var errs []error
    if u.Name == "" {
        errs = append(errs, errors.New("name is required"))
    }
    if u.Email == "" {
        errs = append(errs, errors.New("email is required"))
    }
    if !isValidEmail(u.Email) {
        errs = append(errs, errors.New("email format is invalid"))
    }
    return errors.Join(errs...)
}
```

### Behavior

- Returns `nil` if all input errors are `nil`
- The `Error()` method joins messages with newlines
- `errors.Is` and `errors.As` check every error in the joined set
- The returned error implements `Unwrap() []error`

### When to Use errors.Join

- **Validation** -- collecting all validation errors before returning
- **Batch operations** -- combining errors from independent operations
- **Cleanup** -- combining the original error with cleanup errors
- **Multi-step teardown** -- combining errors from multiple Close() calls

```go
func (db *DB) Close() error {
    return errors.Join(
        db.pool.Close(),
        db.cache.Close(),
        db.metrics.Close(),
    )
}
```

### errors.Join vs Custom Multi-Error

Use `errors.Join` for simple aggregation. Use a custom multi-error type when you need additional structure (error categorization, per-item indexing):

```go
type BatchError struct {
    Index int
    Err   error
}

type BatchErrors struct {
    Errors []BatchError
}

func (e *BatchErrors) Error() string {
    msgs := make([]string, len(e.Errors))
    for i, be := range e.Errors {
        msgs[i] = fmt.Sprintf("item %d: %v", be.Index, be.Err)
    }
    return strings.Join(msgs, "\n")
}

func (e *BatchErrors) Unwrap() []error {
    errs := make([]error, len(e.Errors))
    for i, be := range e.Errors {
        errs[i] = be.Err
    }
    return errs
}
```

## Unwrap Patterns

### Single Unwrap

Errors wrapping a single cause implement `Unwrap() error`:

```go
type QueryError struct {
    Query string
    Err   error
}

func (e *QueryError) Unwrap() error {
    return e.Err
}
```

### Multi Unwrap (Go 1.20+)

Errors wrapping multiple causes implement `Unwrap() []error`:

```go
type MultiError struct {
    Errors []error
}

func (e *MultiError) Unwrap() []error {
    return e.Errors
}
```

Both `errors.Is` and `errors.As` handle both patterns automatically.

### Manual Chain Traversal

In rare cases you may need to walk the chain manually:

```go
func errorChain(err error) []error {
    var chain []error
    for err != nil {
        chain = append(chain, err)
        err = errors.Unwrap(err)
    }
    return chain
}
```

This only follows single-unwrap chains. For multi-errors, use `errors.Is` or `errors.As` instead of manual traversal.

## Common Wrapping Mistakes

### Double Wrapping

Adding context at every level is good, but adding redundant context wastes space:

```go
// Redundant -- "querying" and "executing query" say the same thing
return fmt.Errorf("querying user: %w",
    fmt.Errorf("executing query: %w", err))

// Better -- each level adds distinct context
return fmt.Errorf("finding user by email %s: %w", email, err)
```

### Wrapping nil

`fmt.Errorf` with a `nil` `%w` argument returns a non-nil error:

```go
err := someFunc()
// BUG: if err is nil, this returns a non-nil error with text "operation: <nil>"
return fmt.Errorf("operation: %w", err)

// Correct: always check first
if err != nil {
    return fmt.Errorf("operation: %w", err)
}
return nil
```

### Breaking the Chain Accidentally

Using string concatenation or `fmt.Sprintf` instead of `fmt.Errorf` with `%w` breaks the chain:

```go
// WRONG -- chain is broken, errors.Is will not find the original error
return errors.New("operation failed: " + err.Error())

// WRONG -- %v does not preserve the chain
return fmt.Errorf("operation failed: %v", err)

// CORRECT -- chain is preserved
return fmt.Errorf("operation failed: %w", err)
```

### Wrapping at the Wrong Level

Wrap errors at the point where you have the most context. Do not wrap at every intermediate function if that function adds no useful information:

```go
// Unnecessary wrapping -- adds no context
func (r *repo) helper(ctx context.Context) error {
    return fmt.Errorf("helper: %w", r.doWork(ctx))
}

// Better -- let the error propagate without extra wrapping
func (r *repo) helper(ctx context.Context) error {
    return r.doWork(ctx)
}
```

## Error Wrapping in Practice

### Repository Layer

```go
func (r *UserRepo) FindByID(ctx context.Context, id string) (*User, error) {
    var u User
    err := r.db.QueryRowContext(ctx, "SELECT name, email FROM users WHERE id = $1", id).
        Scan(&u.Name, &u.Email)
    if errors.Is(err, sql.ErrNoRows) {
        return nil, ErrNotFound
    }
    if err != nil {
        return nil, fmt.Errorf("querying user %s: %w", id, err)
    }
    return &u, nil
}
```

### Service Layer

```go
func (s *UserService) GetProfile(ctx context.Context, id string) (*Profile, error) {
    u, err := s.repo.FindByID(ctx, id)
    if err != nil {
        return nil, fmt.Errorf("getting profile for user %s: %w", id, err)
    }
    return toProfile(u), nil
}
```

### Handler Layer (Boundary)

```go
func (h *Handler) GetProfile(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")
    profile, err := h.service.GetProfile(r.Context(), id)
    if errors.Is(err, user.ErrNotFound) {
        http.Error(w, "user not found", http.StatusNotFound)
        return
    }
    if err != nil {
        slog.Error("getting profile", slog.String("user_id", id), slog.Any("error", err))
        http.Error(w, "internal server error", http.StatusInternalServerError)
        return
    }
    writeJSON(w, profile)
}
```

The handler is the boundary: it translates domain errors into HTTP responses and logs the full error for debugging. It does not wrap and return -- it handles the error.

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
