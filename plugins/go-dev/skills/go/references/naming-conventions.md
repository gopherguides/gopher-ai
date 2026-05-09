# Naming Conventions in Go

## Overview

Go names are part of the API. Exported names appear in documentation and are the primary way consumers understand a package. The naming conventions below are not style preferences -- they are community standards that make Go code predictable and readable.

## Identifier Naming

### Variables

Local variables use short names proportional to their scope:

```go
// Short scope: single-letter or abbreviated names
for i, v := range items { ... }
r, err := http.Get(url)
f, err := os.Open(path)
buf := make([]byte, 1024)

// Longer scope: descriptive names
userCount := len(users)
requestTimeout := 30 * time.Second
connectionPool := newPool(cfg)
```

The rule: the further a variable is from its declaration, the more descriptive its name should be.

### Common Short Variable Names

| Name | Usage |
|------|-------|
| `i`, `j`, `k` | Loop indices |
| `v` | Value in range loop |
| `k` | Key in map range |
| `n` | Count or length |
| `err` | Error value |
| `ok` | Boolean result from map lookup, type assertion, channel receive |
| `ctx` | `context.Context` |
| `t` | `*testing.T` |
| `b` | `*testing.B` |
| `r` | `io.Reader`, `*http.Request` |
| `w` | `io.Writer`, `http.ResponseWriter` |
| `s` | String value |
| `buf` | `[]byte` buffer |
| `mu` | `sync.Mutex` |
| `wg` | `sync.WaitGroup` |

### Functions

Function names describe what they return or what they do:

```go
// Returns a value: name describes the value
func ParseConfig(path string) (*Config, error) { ... }
func NewServer(cfg Config) *Server { ... }
func UserByID(id string) (*User, error) { ... }

// Performs an action: name describes the action
func WriteFile(path string, data []byte) error { ... }
func CloseConnection(conn net.Conn) error { ... }
func ValidateEmail(addr string) error { ... }
```

Constructors use the `New` prefix when returning the primary type of a package:

```go
package server
func New(cfg Config) *Server { ... }     // server.New(cfg)

package user
func NewStore(db *sql.DB) *Store { ... } // user.NewStore(db)
```

When a package has a single primary type, prefer `New` over `NewTypeName`:

```go
// Preferred when Server is the primary type
package server
func New(cfg Config) *Server { ... }

// Use NewX when multiple constructors exist
package user
func NewStore(db *sql.DB) *Store { ... }
func NewCache(ttl time.Duration) *Cache { ... }
```

### Types

Type names are nouns or noun phrases:

```go
type Config struct { ... }
type Server struct { ... }
type UserStore struct { ... }
type RequestHandler struct { ... }
type ValidationError struct { ... }
```

Interface names use the `-er` suffix when the interface has a single method:

```go
type Reader interface { Read(p []byte) (n int, err error) }
type Writer interface { Write(p []byte) (n int, err error) }
type Closer interface { Close() error }
type Stringer interface { String() string }
type Handler interface { ServeHTTP(ResponseWriter, *Request) }
```

Multi-method interfaces describe their behavior:

```go
type ReadWriter interface {
    Reader
    Writer
}

type Store interface {
    Get(ctx context.Context, id string) (*User, error)
    Put(ctx context.Context, user *User) error
    Delete(ctx context.Context, id string) error
}
```

### Constants

Constants use MixedCaps like all Go identifiers. Do not use ALL_CAPS:

```go
// Correct
const MaxRetries = 3
const defaultTimeout = 30 * time.Second

// Wrong -- not Go style
const MAX_RETRIES = 3
const DEFAULT_TIMEOUT = 30 * time.Second
```

Grouped constants with iota:

```go
type Role int

const (
    RoleAdmin Role = iota
    RoleEditor
    RoleViewer
)
```

## Acronym Handling

Go has specific rules for acronyms and initialisms. The rule: acronyms are either all uppercase or all lowercase. Never mixed case.

### Exported Identifiers (all uppercase)

```go
type HTTPClient struct { ... }
type URLParser struct { ... }
type XMLDecoder struct { ... }
func ServeHTTP(w http.ResponseWriter, r *http.Request) { ... }
func ParseURL(raw string) (*URL, error) { ... }
func NewHTTPServer(addr string) *HTTPServer { ... }
var DefaultHTTPClient = &HTTPClient{}
const MaxURLLength = 2048
```

### Unexported Identifiers (all lowercase)

```go
var httpClient = &http.Client{}
func parseURL(raw string) (*url.URL, error) { ... }
func newHTTPServer(addr string) *httpServer { ... }
var defaultHTTPTimeout = 30 * time.Second
```

### Common Acronyms

| Acronym | Exported | Unexported |
|---------|----------|------------|
| API | `API` | `api` |
| CSS | `CSS` | `css` |
| DNS | `DNS` | `dns` |
| EOF | `EOF` | `eof` |
| HTML | `HTML` | `html` |
| HTTP | `HTTP` | `http` |
| HTTPS | `HTTPS` | `https` |
| ID | `ID` | `id` |
| IP | `IP` | `ip` |
| JSON | `JSON` | `json` |
| SQL | `SQL` | `sql` |
| SSH | `SSH` | `ssh` |
| TCP | `TCP` | `tcp` |
| TLS | `TLS` | `tls` |
| TTL | `TTL` | `ttl` |
| UDP | `UDP` | `udp` |
| URL | `URL` | `url` |
| UTF8 | `UTF8` | `utf8` |
| UUID | `UUID` | `uuid` |
| XML | `XML` | `xml` |

### Compound Names with Acronyms

When an acronym appears mid-name, keep it all-caps for exported and all-lower for unexported:

```go
// Exported
type HTTPSHandler struct { ... }
func GetUserID(ctx context.Context) string { ... }
func ParseJSONResponse(r io.Reader) (*Response, error) { ... }
type SQLStore struct { ... }

// Unexported
func getUserID(ctx context.Context) string { ... }
func parseJSONResponse(r io.Reader) (*response, error) { ... }
type sqlStore struct { ... }
```

### ID vs Id

`ID` is one of the most commonly mishandled acronyms:

```go
// Correct
type UserID string
func GetUserID() string { ... }
func (u *User) ID() string { ... }
var userID string

// Wrong
type UserId string
func GetUserId() string { ... }
func (u *User) Id() string { ... }
var userId string
```

## Receiver Naming

Method receivers use short names (one or two letters), derived from the type name, and are consistent across all methods of a type:

```go
// Correct: short, derived from type name
func (s *Server) Start() error { ... }
func (s *Server) Stop() error { ... }
func (s *Server) Handler() http.Handler { ... }

func (c *Client) Do(req *Request) (*Response, error) { ... }
func (c *Client) Close() error { ... }

func (uc *UserCache) Get(id string) (*User, bool) { ... }
func (uc *UserCache) Set(id string, u *User) { ... }
```

```go
// Wrong: too long, inconsistent
func (server *Server) Start() error { ... }
func (srv *Server) Stop() error { ... }
func (self *Server) Handler() http.Handler { ... }
```

### Rules

- One or two letters, derived from the type abbreviation
- Same receiver name across ALL methods of a type
- Never use `self` or `this`
- Use pointer receiver `*T` when the method mutates state or the type is large
- Use value receiver `T` for small, immutable types

### Decision Table for Receiver Names

| Type | Receiver |
|------|----------|
| `Server` | `s` |
| `Client` | `c` |
| `Handler` | `h` |
| `Store` | `s` |
| `UserStore` | `us` |
| `UserCache` | `uc` |
| `Config` | `c` |
| `Response` | `r` |
| `Request` | `r` |
| `Buffer` | `b` |
| `Logger` | `l` |
| `Middleware` | `m` |
| `Router` | `r` |
| `Validator` | `v` |

## File Naming

### Rules

- Lowercase with underscores: `user_store.go`, `http_handler.go`
- Name files after what they contain, not the type: `store.go` not `user_store_type.go`
- One primary type or concern per file
- Test files: `<name>_test.go` (same package or `_test` suffix package)

### Standard File Names

| File | Contents |
|------|----------|
| `doc.go` | Package documentation (package comment only) |
| `<type>.go` | Type definition and its methods |
| `<type>_test.go` | Tests for that type |
| `example_test.go` | Testable examples for the package |
| `export_test.go` | Exported test helpers (in `_test` package, accessing unexported internals) |
| `bench_test.go` | Benchmarks (when separated from unit tests) |

### Platform-Specific Files

Go uses build constraints and filename conventions for platform-specific code:

```
store_linux.go       // only built on Linux
store_darwin.go      // only built on macOS
store_windows.go     // only built on Windows
store_amd64.go       // only built for amd64 architecture
```

### Test File Naming

Test files mirror the files they test:

```
user.go          -> user_test.go
store.go         -> store_test.go
http_handler.go  -> http_handler_test.go
```

Black-box tests (testing only the exported API) use the `_test` package suffix:

```go
// In user_test.go
package user_test

import "myapp/user"
```

White-box tests (testing internals) use the same package:

```go
// In user_test.go
package user
```

Prefer black-box tests. Use white-box tests only when testing unexported behavior that cannot be exercised through the public API.

### Generated File Conventions

Generated files include a comment identifying them:

```go
// Code generated by <tool>; DO NOT EDIT.
```

This comment must appear before the package clause. Tools like `go generate` and linters recognize this pattern and skip generated files.

Common generated file patterns:

```
<name>_string.go     // stringer output
<name>_gen.go        // general generated code
<name>.pb.go         // protobuf generated code
<name>_templ.go      // templ generated code
mock_<name>.go       // generated mocks
```

## Naming Decision Table

| Situation | Pattern | Example |
|-----------|---------|---------|
| Package primary type constructor | `New` | `server.New(cfg)` |
| Package secondary type constructor | `NewX` | `user.NewStore(db)` |
| Getter method | Just the field name | `u.Name()` not `u.GetName()` |
| Setter method | `Set` prefix | `u.SetName(n)` |
| Boolean method | `Is`/`Has`/`Can` prefix | `u.IsAdmin()`, `f.HasHeader()` |
| Conversion method | `To`/`As` prefix | `t.ToJSON()`, `n.AsFloat64()` |
| Test helper | `new`/`must` prefix (unexported) | `newTestServer(t)`, `mustParse(t, s)` |
| Sentinel error | `Err` prefix | `ErrNotFound` |
| Custom error type | `Error` suffix | `ValidationError` |
| Interface (single method) | `-er` suffix | `Reader`, `Writer`, `Closer` |
| Interface (behavior) | Descriptive noun | `Store`, `Authenticator` |
| Unexported constant | `camelCase` | `defaultTimeout` |
| Exported constant | `MixedCaps` | `MaxRetries` |
| Enum type | Named type on `int` or `string` | `type Role int` |
| Enum values | Type prefix | `RoleAdmin`, `RoleEditor` |
