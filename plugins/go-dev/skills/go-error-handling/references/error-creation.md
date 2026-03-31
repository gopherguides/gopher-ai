# Error Creation in Go

## Overview

Go provides two primary mechanisms for creating errors: `errors.New` for simple static errors and `fmt.Errorf` for errors with dynamic context. For errors that need to carry structured data, implement the `error` interface with a custom type.

## Sentinel Errors

Sentinel errors are package-level variables created with `errors.New`. They represent known, expected error conditions that callers check for by identity.

### When to Use Sentinels

- The error represents an expected condition (not found, already exists, permission denied)
- Callers need to branch on the error identity using `errors.Is`
- The error message is static and does not change at runtime
- The error does not need to carry additional data beyond its identity

### Naming Convention

Sentinel errors use the `Err` prefix followed by the condition name:

```go
var (
    ErrNotFound     = errors.New("not found")
    ErrUnauthorized = errors.New("unauthorized")
    ErrConflict     = errors.New("conflict")
)
```

The variable name communicates the condition. The error string is lowercase with no trailing punctuation, following Go convention.

### Package-Level Declaration

Declare sentinel errors at the package level as exported variables. Group related sentinels together:

```go
package user

import "errors"

var (
    ErrNotFound      = errors.New("user not found")
    ErrAlreadyExists = errors.New("user already exists")
    ErrInvalidEmail  = errors.New("invalid email address")
)
```

### Checking Sentinel Errors

Callers use `errors.Is` to check for sentinels through wrapped error chains:

```go
result, err := users.FindByEmail(ctx, email)
if errors.Is(err, user.ErrNotFound) {
    return nil, fmt.Errorf("no account for %s: %w", email, err)
}
if err != nil {
    return nil, fmt.Errorf("finding user by email: %w", err)
}
```

NEVER compare sentinel errors with `==`. The `errors.Is` function traverses the full error chain, handling wrapped errors correctly.

### Sentinel Anti-Patterns

Avoid creating sentinel errors for conditions that are better handled by the type system:

```go
// Avoid -- sentinel for a condition that needs data
var ErrValidation = errors.New("validation error")

// The caller cannot determine WHICH validation failed without
// parsing the error string. Use a custom error type instead.
```

Avoid creating too many sentinels. If a package has more than 5-7 sentinel errors, some of them likely belong in a custom error type with a kind or code field.

## Dynamic Errors with fmt.Errorf

Use `fmt.Errorf` when the error message needs runtime values:

```go
func LoadConfig(path string) (*Config, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return nil, fmt.Errorf("reading config %s: %w", path, err)
    }

    var cfg Config
    if err := json.Unmarshal(data, &cfg); err != nil {
        return nil, fmt.Errorf("parsing config %s: %w", path, err)
    }

    return &cfg, nil
}
```

### Wrapping with %w

Use `%w` to wrap the original error, preserving the error chain for `errors.Is` and `errors.As`:

```go
return fmt.Errorf("connecting to database: %w", err)
```

### Opaque with %v

Use `%v` to include the error text without preserving the chain. This is appropriate at system boundaries where you do not want callers depending on internal error types:

```go
return fmt.Errorf("service unavailable: %v", err)
```

See [error-wrapping.md](error-wrapping.md) for detailed guidance on when to use each verb.

## Custom Error Types

Custom error types implement the `error` interface and carry structured data about the failure.

### When to Use Custom Types

- The error needs to carry structured data (field name, expected vs actual, HTTP status code)
- Callers need to extract specific information from the error using `errors.As`
- A sentinel is insufficient because the same kind of error occurs with different details
- You want to attach multiple pieces of context that callers might need programmatically

### Naming Convention

Custom error types use the `Error` suffix:

```go
type NotFoundError struct {
    Resource string
    ID       string
}

func (e *NotFoundError) Error() string {
    return fmt.Sprintf("%s %s not found", e.Resource, e.ID)
}
```

### Implementing the error Interface

The `error` interface requires a single method:

```go
type error interface {
    Error() string
}
```

Use a pointer receiver for the `Error()` method. This avoids copying the struct on every call and ensures `errors.As` works correctly with pointer targets:

```go
type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation failed on %s: %s", e.Field, e.Message)
}
```

### Constructor Functions

Provide constructor functions to ensure errors are created correctly:

```go
func NewValidationError(field, message string) *ValidationError {
    return &ValidationError{
        Field:   field,
        Message: message,
    }
}
```

### Wrapping with Custom Types

Custom error types can wrap underlying errors by implementing the `Unwrap` method:

```go
type QueryError struct {
    Query string
    Err   error
}

func (e *QueryError) Error() string {
    return fmt.Sprintf("query %q failed: %v", e.Query, e.Err)
}

func (e *QueryError) Unwrap() error {
    return e.Err
}
```

This allows `errors.Is` and `errors.As` to traverse through the custom error to the wrapped cause:

```go
qErr := &QueryError{
    Query: "SELECT * FROM users",
    Err:   sql.ErrNoRows,
}

errors.Is(qErr, sql.ErrNoRows) // true
```

### Extracting Custom Errors

Callers use `errors.As` to extract custom error types from a chain:

```go
var vErr *ValidationError
if errors.As(err, &vErr) {
    slog.Warn("validation failed",
        slog.String("field", vErr.Field),
        slog.String("message", vErr.Message),
    )
    return badRequestResponse(vErr.Field, vErr.Message)
}
```

### Multi-Error Custom Types

For operations that can produce multiple independent errors (validation, batch processing), implement `Unwrap() []error`:

```go
type MultiValidationError struct {
    Errors []error
}

func (e *MultiValidationError) Error() string {
    msgs := make([]string, len(e.Errors))
    for i, err := range e.Errors {
        msgs[i] = err.Error()
    }
    return fmt.Sprintf("validation failed: %s", strings.Join(msgs, "; "))
}

func (e *MultiValidationError) Unwrap() []error {
    return e.Errors
}
```

With `Unwrap() []error`, `errors.Is` and `errors.As` check every error in the tree.

## Decision Table: Sentinel vs Custom Type

| Criterion | Sentinel Error | Custom Error Type |
|-----------|---------------|-------------------|
| Error message | Static, never changes | Dynamic, includes runtime data |
| Caller needs | Identity check only (`errors.Is`) | Data extraction (`errors.As`) |
| Number of variants | Few (< 7 per package) | Many, differentiated by field values |
| Structured data | None | Fields carrying context |
| Wrapping | Not applicable (leaf error) | Can wrap underlying cause |
| Typical use | Not found, unauthorized, conflict | Validation error, query error, HTTP error |

### Hybrid Approach

Some packages combine both: a custom error type with a sentinel for the common case:

```go
var ErrValidation = errors.New("validation error")

type ValidationError struct {
    Field   string
    Message string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: %s: %s", e.Field, e.Message)
}

func (e *ValidationError) Is(target error) bool {
    return target == ErrValidation
}
```

This allows callers to check broadly with `errors.Is(err, ErrValidation)` or extract details with `errors.As(err, &vErr)`.

## Error Message Guidelines

1. Start lowercase -- Go convention for error strings
2. No trailing punctuation -- errors are often wrapped, and punctuation composes poorly
3. Include the operation that failed -- `"reading config"`, not `"config error"`
4. Include relevant identifiers -- `"reading config /etc/app.yaml"`, not just `"reading config"`
5. Keep messages low-cardinality for structured logging -- attach high-cardinality data as separate fields
6. Avoid redundant type information -- `"not found"` not `"NotFoundError: not found"`
7. Use present participle for wrapping context -- `"connecting to database"`, `"parsing response"`

```go
// Good error messages
"connecting to database"
"reading config /etc/app.yaml"
"user not found"
"validation failed on email"

// Bad error messages
"Error: Failed to connect to the database."  // uppercase, trailing punctuation
"DB_CONNECTION_ERROR"                         // not human-readable
"error occurred while attempting to connect"  // verbose, redundant "error"
```

## Standard Library Error Patterns

### io.EOF

`io.EOF` is the canonical sentinel error. It signals a normal end-of-stream condition, not a failure:

```go
for {
    line, err := reader.ReadString('\n')
    if errors.Is(err, io.EOF) {
        break
    }
    if err != nil {
        return fmt.Errorf("reading line: %w", err)
    }
    process(line)
}
```

Never wrap `io.EOF` with `%w` if the caller expects to check for it. The wrapping changes the identity. Instead, handle it at the point of detection.

### context.Canceled and context.DeadlineExceeded

These are sentinels from the `context` package. Check for them at cancellation boundaries:

```go
result, err := longOperation(ctx)
if errors.Is(err, context.DeadlineExceeded) {
    slog.Warn("operation timed out", slog.Duration("timeout", timeout))
    return nil, fmt.Errorf("operation timed out after %v: %w", timeout, err)
}
if errors.Is(err, context.Canceled) {
    return nil, err
}
```

### sql.ErrNoRows

A common source of bugs. Always handle it explicitly rather than treating it as an unexpected error:

```go
var u User
err := db.QueryRowContext(ctx, query, id).Scan(&u.Name, &u.Email)
if errors.Is(err, sql.ErrNoRows) {
    return nil, ErrNotFound
}
if err != nil {
    return nil, fmt.Errorf("querying user %s: %w", id, err)
}
```

Translate `sql.ErrNoRows` to a domain-level sentinel at the repository boundary. Callers should not depend on database-specific errors.

## Testing Error Creation

### Testing Sentinels

```go
func TestFindUser_NotFound(t *testing.T) {
    _, err := repo.FindUser(ctx, "nonexistent-id")
    if !errors.Is(err, user.ErrNotFound) {
        t.Errorf("got %v, want %v", err, user.ErrNotFound)
    }
}
```

### Testing Custom Error Types

```go
func TestValidate_InvalidEmail(t *testing.T) {
    err := Validate(User{Email: "bad"})

    var vErr *ValidationError
    if !errors.As(err, &vErr) {
        t.Fatalf("expected ValidationError, got %T: %v", err, err)
    }
    if vErr.Field != "email" {
        t.Errorf("field = %q, want %q", vErr.Field, "email")
    }
}
```

### Testing Error Messages

Avoid testing exact error message strings. Test the error identity or type instead. If you must test the message, use `strings.Contains` for resilience:

```go
if !strings.Contains(err.Error(), "config") {
    t.Errorf("error should mention config, got: %v", err)
}
```

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
