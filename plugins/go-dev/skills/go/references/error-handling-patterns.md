# Error Handling Patterns in Go

## The Single Handling Rule

Handle every error exactly once. Either log it and handle the failure, or wrap it with context and return it. Never both, never neither.

### Why This Rule Exists

When an error is both logged and returned, every caller up the stack that also logs before returning creates duplicate log entries. In a 5-layer call stack, a single database error can produce 5 log lines -- all for the same root cause. This noise makes it harder to diagnose issues in production, inflates log storage costs, and triggers duplicate alerts.

### Log OR Return

```go
// CORRECT: return with context, let the caller decide how to handle it
func (s *OrderService) Place(ctx context.Context, o Order) error {
    if err := s.inventory.Reserve(ctx, o.Items); err != nil {
        return fmt.Errorf("reserving inventory for order %s: %w", o.ID, err)
    }
    return nil
}

// CORRECT: log and handle (do not return the error)
func (h *OrderHandler) PlaceOrder(w http.ResponseWriter, r *http.Request) {
    var o Order
    if err := json.NewDecoder(r.Body).Decode(&o); err != nil {
        slog.Warn("invalid order request",
            slog.String("remote_addr", r.RemoteAddr),
            slog.Any("error", err),
        )
        http.Error(w, "invalid request body", http.StatusBadRequest)
        return
    }

    if err := h.service.Place(r.Context(), o); err != nil {
        slog.Error("placing order",
            slog.String("order_id", o.ID),
            slog.Any("error", err),
        )
        http.Error(w, "internal server error", http.StatusInternalServerError)
        return
    }

    w.WriteHeader(http.StatusCreated)
}
```

### The Violation Pattern

```go
// VIOLATION: logs AND returns -- every caller that also logs creates duplicates
func (s *OrderService) Place(ctx context.Context, o Order) error {
    if err := s.inventory.Reserve(ctx, o.Items); err != nil {
        log.Printf("failed to reserve inventory: %v", err) // logged here
        return fmt.Errorf("reserving inventory: %w", err)   // AND returned
    }
    return nil
}
```

### Where to Log

The general rule: log at the top of the call stack, where the error is finally handled. In a web application, this is typically the HTTP handler or middleware. In a CLI, this is the main function or command runner.

```
main / handler / middleware   ← LOG here (top of stack)
    ↑ return wrapped error
service layer                 ← WRAP and RETURN
    ↑ return wrapped error
repository layer              ← WRAP and RETURN
    ↑ return raw error
database driver               ← ORIGIN
```

### Exceptions to Single Handling

There are two narrow exceptions where logging before returning is acceptable:

1. **Degraded operation** -- The function logs a warning, falls back to a degraded path, and continues. The error is not returned because the operation succeeded (in degraded mode):

```go
func (s *Service) GetConfig(ctx context.Context) (*Config, error) {
    cfg, err := s.cache.Get(ctx, "config")
    if err != nil {
        slog.Warn("cache miss, falling back to database", slog.Any("error", err))
        return s.db.GetConfig(ctx)
    }
    return cfg, nil
}
```

2. **Boundary crossing with additional context** -- At a major system boundary (e.g., entering a background worker), you log with boundary-specific context that will be lost if only returned:

```go
func (w *Worker) processJob(ctx context.Context, job Job) error {
    err := w.handler.Handle(ctx, job)
    if err != nil {
        slog.Error("job processing failed",
            slog.String("job_id", job.ID),
            slog.String("queue", job.Queue),
            slog.Int("attempt", job.Attempt),
            slog.Any("error", err),
        )
        return fmt.Errorf("processing job %s: %w", job.ID, err)
    }
    return nil
}
```

In this case, the boundary-specific context (queue, attempt number) enriches the log beyond what the error chain carries. This is a judgment call -- if the caller will log with the same context, it is still a violation.

## Panic and Recover

### When Panic Is Acceptable

`panic` is reserved for truly unrecoverable states where continuing execution would be dangerous or produce corrupt results:

- **Programming errors** -- nil pointer dereference, index out of bounds, impossible states that indicate a bug
- **Initialization failures** -- a required dependency that cannot be created (database connection in `main()`, required environment variable missing)
- **Violated invariants** -- a state that the program's logic guarantees cannot occur

```go
func MustParseTemplate(name string) *template.Template {
    t, err := template.ParseFiles(name)
    if err != nil {
        panic(fmt.Sprintf("parsing template %s: %v", name, err))
    }
    return t
}
```

The `Must` prefix is the Go convention for functions that panic on error. Use these only during program initialization, never in request-handling code paths.

### When Panic Is NOT Acceptable

- User input validation failures
- Network errors, timeouts, connection refused
- File not found, permission denied
- Database query errors
- Any condition that can occur during normal operation

For all of these, return an error.

### Recover Patterns

`recover()` must be called inside a deferred function. It returns `nil` if no panic is in progress, or the panic value if one is.

#### HTTP Server Recovery Middleware

```go
func RecoveryMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        defer func() {
            if v := recover(); v != nil {
                stack := debug.Stack()
                slog.Error("panic recovered",
                    slog.Any("panic", v),
                    slog.String("stack", string(stack)),
                    slog.String("method", r.Method),
                    slog.String("path", r.URL.Path),
                )
                http.Error(w, "internal server error", http.StatusInternalServerError)
            }
        }()
        next.ServeHTTP(w, r)
    })
}
```

#### Converting Panic to Error

In library code that must not crash the caller:

```go
func SafeExecute(fn func() error) (err error) {
    defer func() {
        if v := recover(); v != nil {
            err = fmt.Errorf("panic: %v\n%s", v, debug.Stack())
        }
    }()
    return fn()
}
```

The named return value `err` is critical -- the deferred function assigns the panic-converted error to it.

#### Recover Scope Rules

`recover()` only catches panics in the same goroutine. A panic in a child goroutine will crash the program regardless of recover in the parent:

```go
func main() {
    defer func() {
        recover() // does NOT catch panics in child goroutines
    }()

    go func() {
        panic("this crashes the program")
    }()

    time.Sleep(time.Second)
}
```

Each goroutine that might panic needs its own recover:

```go
func safeGo(fn func()) {
    go func() {
        defer func() {
            if v := recover(); v != nil {
                slog.Error("goroutine panic", slog.Any("panic", v))
            }
        }()
        fn()
    }()
}
```

### Panic in Tests

`testing.T.Fatal` and `testing.T.FailNow` use `runtime.Goexit()`, not `panic`. They cannot be called from goroutines other than the test goroutine. Use channels or `t.Errorf` (which is safe from any goroutine) instead.

## Structured Error Logging with slog

### Why slog

Go 1.21 introduced `log/slog` as the standard structured logging package. Structured logging is essential for error handling because:

- Log aggregation systems (Datadog, Grafana Loki, CloudWatch) can index and search structured fields
- Error attributes (user ID, request ID, operation) become filterable dimensions
- Low-cardinality log messages with high-cardinality attributes scale better than interpolated strings

### Logging Errors with slog

```go
slog.Error("placing order",
    slog.String("order_id", order.ID),
    slog.String("user_id", userID),
    slog.Any("error", err),
)
```

This produces structured output:

```json
{
    "time": "2024-01-15T10:30:00Z",
    "level": "ERROR",
    "msg": "placing order",
    "order_id": "ord-123",
    "user_id": "usr-456",
    "error": "reserving inventory for order ord-123: insufficient stock"
}
```

### Error Attributes Best Practices

Pass the error as a structured attribute, not interpolated into the message:

```go
// WRONG -- high-cardinality message, hard to aggregate
slog.Error(fmt.Sprintf("placing order %s failed: %v", order.ID, err))

// CORRECT -- low-cardinality message, error as separate attribute
slog.Error("placing order",
    slog.String("order_id", order.ID),
    slog.Any("error", err),
)
```

### Log Levels for Errors

| Level | When |
|-------|------|
| `slog.Error` | Unexpected failure that needs investigation |
| `slog.Warn` | Expected failure handled gracefully (cache miss, retry) |
| `slog.Info` | Normal operation completion (request served) |
| `slog.Debug` | Diagnostic detail (query parameters, intermediate values) |

### Adding Context with slog.With

Use `slog.With` to create loggers with pre-attached context for a request scope:

```go
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    logger := slog.With(
        slog.String("request_id", r.Header.Get("X-Request-ID")),
        slog.String("method", r.Method),
        slog.String("path", r.URL.Path),
    )

    result, err := h.service.Process(r.Context())
    if err != nil {
        logger.Error("request failed", slog.Any("error", err))
        http.Error(w, "internal server error", http.StatusInternalServerError)
        return
    }

    logger.Info("request completed", slog.Int("items", len(result)))
}
```

### Migrating from log to slog

Replace common `log` patterns:

```go
// Before
log.Printf("error processing order %s: %v", orderID, err)

// After
slog.Error("processing order",
    slog.String("order_id", orderID),
    slog.Any("error", err),
)
```

```go
// Before
log.Fatalf("failed to connect to database: %v", err)

// After -- slog does not have Fatal; handle the error explicitly
slog.Error("connecting to database", slog.Any("error", err))
os.Exit(1)
```

## HTTP Error Translation

### The Translation Layer

HTTP handlers translate domain errors into HTTP responses. This is where the single handling rule terminates -- the handler logs the error and sends an appropriate response:

```go
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
    id := chi.URLParam(r, "id")

    u, err := h.service.Find(r.Context(), id)
    if err != nil {
        h.handleError(w, r, err)
        return
    }

    writeJSON(w, http.StatusOK, u)
}

func (h *Handler) handleError(w http.ResponseWriter, r *http.Request, err error) {
    logger := slog.With(
        slog.String("method", r.Method),
        slog.String("path", r.URL.Path),
    )

    switch {
    case errors.Is(err, user.ErrNotFound):
        logger.Info("resource not found", slog.Any("error", err))
        writeJSON(w, http.StatusNotFound, errorResponse{Message: "not found"})

    case errors.Is(err, user.ErrConflict):
        logger.Info("conflict", slog.Any("error", err))
        writeJSON(w, http.StatusConflict, errorResponse{Message: "already exists"})

    case errors.Is(err, context.DeadlineExceeded):
        logger.Warn("request timeout", slog.Any("error", err))
        writeJSON(w, http.StatusGatewayTimeout, errorResponse{Message: "request timed out"})

    default:
        var vErr *ValidationError
        if errors.As(err, &vErr) {
            logger.Info("validation error",
                slog.String("field", vErr.Field),
                slog.Any("error", err),
            )
            writeJSON(w, http.StatusBadRequest, errorResponse{
                Message: vErr.Message,
                Field:   vErr.Field,
            })
            return
        }

        logger.Error("unhandled error", slog.Any("error", err))
        writeJSON(w, http.StatusInternalServerError, errorResponse{Message: "internal server error"})
    }
}

type errorResponse struct {
    Message string `json:"message"`
    Field   string `json:"field,omitempty"`
}
```

### Error Translation Middleware

For applications with many handlers, centralize error translation in middleware:

```go
type HandlerFunc func(w http.ResponseWriter, r *http.Request) error

func ErrorMiddleware(h HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        err := h(w, r)
        if err == nil {
            return
        }

        logger := slog.With(
            slog.String("method", r.Method),
            slog.String("path", r.URL.Path),
        )

        code, msg := translateError(err)
        logger.Log(r.Context(), levelForStatus(code), "request error",
            slog.Int("status", code),
            slog.Any("error", err),
        )
        writeJSON(w, code, errorResponse{Message: msg})
    }
}

func translateError(err error) (int, string) {
    switch {
    case errors.Is(err, ErrNotFound):
        return http.StatusNotFound, "not found"
    case errors.Is(err, ErrUnauthorized):
        return http.StatusUnauthorized, "unauthorized"
    case errors.Is(err, ErrConflict):
        return http.StatusConflict, "already exists"
    case errors.Is(err, context.DeadlineExceeded):
        return http.StatusGatewayTimeout, "request timed out"
    default:
        var vErr *ValidationError
        if errors.As(err, &vErr) {
            return http.StatusBadRequest, vErr.Message
        }
        return http.StatusInternalServerError, "internal server error"
    }
}

func levelForStatus(code int) slog.Level {
    if code >= 500 {
        return slog.LevelError
    }
    return slog.LevelInfo
}
```

### Never Expose Internal Errors

The error response sent to the client must NEVER contain internal error details:

```go
// WRONG -- exposes internal details
http.Error(w, err.Error(), http.StatusInternalServerError)

// WRONG -- exposes database schema information
writeJSON(w, http.StatusInternalServerError, map[string]string{
    "error": fmt.Sprintf("query failed: %v", err),
})

// CORRECT -- generic message, full error logged server-side
slog.Error("query failed", slog.Any("error", err))
http.Error(w, "internal server error", http.StatusInternalServerError)
```

Internal error details can reveal database schemas, file paths, service names, and other information useful to attackers.

## Error Handling in Background Workers

Background workers (job processors, event consumers) are error handling boundaries similar to HTTP handlers:

```go
func (w *Worker) Run(ctx context.Context) error {
    for {
        select {
        case <-ctx.Done():
            return ctx.Err()
        case job := <-w.jobs:
            if err := w.process(ctx, job); err != nil {
                slog.Error("job failed",
                    slog.String("job_id", job.ID),
                    slog.String("type", job.Type),
                    slog.Int("attempt", job.Attempt),
                    slog.Any("error", err),
                )
                if err := w.queue.Retry(ctx, job); err != nil {
                    slog.Error("failed to retry job",
                        slog.String("job_id", job.ID),
                        slog.Any("error", err),
                    )
                }
                continue
            }
            slog.Info("job completed",
                slog.String("job_id", job.ID),
                slog.String("type", job.Type),
            )
        }
    }
}
```

## Error Handling in Cleanup (defer)

When a deferred cleanup function can fail, combine its error with the function's return error:

```go
func WriteFile(path string, data []byte) (err error) {
    f, createErr := os.Create(path)
    if createErr != nil {
        return fmt.Errorf("creating file %s: %w", path, createErr)
    }
    defer func() {
        closeErr := f.Close()
        err = errors.Join(err, closeErr)
    }()

    if _, writeErr := f.Write(data); writeErr != nil {
        return fmt.Errorf("writing to %s: %w", path, writeErr)
    }
    return nil
}
```

The named return value `err` allows the deferred function to modify the return value. Using `errors.Join` preserves both errors when both the write and close fail.

## Retry Patterns

For transient errors (network timeouts, temporary unavailability), implement retry with backoff:

```go
func withRetry(ctx context.Context, maxAttempts int, fn func() error) error {
    var err error
    for attempt := range maxAttempts {
        err = fn()
        if err == nil {
            return nil
        }
        if !isRetryable(err) {
            return fmt.Errorf("non-retryable error on attempt %d: %w", attempt+1, err)
        }
        backoff := time.Duration(attempt+1) * 100 * time.Millisecond
        select {
        case <-ctx.Done():
            return fmt.Errorf("retry canceled: %w", errors.Join(ctx.Err(), err))
        case <-time.After(backoff):
        }
    }
    return fmt.Errorf("all %d attempts failed: %w", maxAttempts, err)
}

func isRetryable(err error) bool {
    return errors.Is(err, context.DeadlineExceeded) ||
        errors.Is(err, syscall.ECONNREFUSED) ||
        errors.Is(err, syscall.ECONNRESET)
}
```

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
