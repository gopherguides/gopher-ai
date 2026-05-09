# Interface Patterns in Go

## Decorator / Wrapper Pattern

Add behavior to an existing interface implementation without modifying it. The decorator accepts and returns the same interface.

### Logging Decorator

```go
type Logger interface {
    Printf(format string, args ...any)
}

type UserStore interface {
    GetUser(id string) (User, error)
    SaveUser(u User) error
}

type loggingUserStore struct {
    next   UserStore
    logger Logger
}

func NewLoggingUserStore(next UserStore, logger Logger) UserStore {
    return &loggingUserStore{next: next, logger: logger}
}

func (s *loggingUserStore) GetUser(id string) (User, error) {
    s.logger.Printf("GetUser called with id=%s", id)
    u, err := s.next.GetUser(id)
    if err != nil {
        s.logger.Printf("GetUser error: %v", err)
    }
    return u, err
}

func (s *loggingUserStore) SaveUser(u User) error {
    s.logger.Printf("SaveUser called for user=%s", u.ID)
    return s.next.SaveUser(u)
}
```

### Retry Decorator

```go
type Doer interface {
    Do(ctx context.Context) error
}

type retryDoer struct {
    next       Doer
    maxRetries int
    backoff    time.Duration
}

func WithRetry(next Doer, maxRetries int, backoff time.Duration) Doer {
    return &retryDoer{next: next, maxRetries: maxRetries, backoff: backoff}
}

func (r *retryDoer) Do(ctx context.Context) error {
    var lastErr error
    for attempt := range r.maxRetries {
        lastErr = r.next.Do(ctx)
        if lastErr == nil {
            return nil
        }
        select {
        case <-ctx.Done():
            return ctx.Err()
        case <-time.After(r.backoff * time.Duration(attempt+1)):
        }
    }
    return fmt.Errorf("failed after %d attempts: %w", r.maxRetries, lastErr)
}
```

Decorators compose. Wrap logging around retry around the real implementation:

```go
var store UserStore = NewPostgresStore(db)
store = NewLoggingUserStore(store, logger)
```

## Middleware Pattern

A specialization of the decorator pattern used extensively with `http.Handler`. Middleware wraps a handler to add cross-cutting concerns.

### Basic Middleware

```go
func WithRequestID(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        id := uuid.New().String()
        ctx := context.WithValue(r.Context(), requestIDKey, id)
        w.Header().Set("X-Request-ID", id)
        next.ServeHTTP(w, r.WithContext(ctx))
    })
}
```

### Timing Middleware

```go
func WithTiming(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        next.ServeHTTP(w, r)
        duration := time.Since(start)
        log.Printf("%s %s took %v", r.Method, r.URL.Path, duration)
    })
}
```

### Response Capturing Middleware

```go
type statusRecorder struct {
    http.ResponseWriter
    statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.statusCode = code
    r.ResponseWriter.WriteHeader(code)
}

func WithMetrics(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        rec := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}
        next.ServeHTTP(rec, r)
        requestCount.WithLabelValues(r.Method, strconv.Itoa(rec.statusCode)).Inc()
    })
}
```

### Middleware Chaining

```go
func Chain(h http.Handler, middlewares ...func(http.Handler) http.Handler) http.Handler {
    for i := len(middlewares) - 1; i >= 0; i-- {
        h = middlewares[i](h)
    }
    return h
}

handler := Chain(
    myHandler,
    WithRequestID,
    WithTiming,
    WithMetrics,
)
```

Middlewares execute in the order listed. `WithRequestID` runs first (outermost), `WithMetrics` runs last (innermost, closest to the handler).

## Functional Options with Interfaces

Use interfaces to make option types extensible and testable.

### Basic Functional Options

```go
type Server struct {
    addr         string
    readTimeout  time.Duration
    writeTimeout time.Duration
    handler      http.Handler
}

type Option func(*Server)

func WithAddr(addr string) Option {
    return func(s *Server) {
        s.addr = addr
    }
}

func WithTimeouts(read, write time.Duration) Option {
    return func(s *Server) {
        s.readTimeout = read
        s.writeTimeout = write
    }
}

func NewServer(handler http.Handler, opts ...Option) *Server {
    s := &Server{
        addr:         ":8080",
        readTimeout:  5 * time.Second,
        writeTimeout: 10 * time.Second,
        handler:      handler,
    }
    for _, opt := range opts {
        opt(s)
    }
    return s
}
```

### Interface-Based Options

When options need validation or need to be inspectable:

```go
type Option interface {
    apply(*Server) error
}

type addrOption struct {
    addr string
}

func (o addrOption) apply(s *Server) error {
    if o.addr == "" {
        return fmt.Errorf("address must not be empty")
    }
    s.addr = o.addr
    return nil
}

func WithAddr(addr string) Option {
    return addrOption{addr: addr}
}

func NewServer(handler http.Handler, opts ...Option) (*Server, error) {
    s := &Server{
        addr:    ":8080",
        handler: handler,
    }
    for _, opt := range opts {
        if err := opt.apply(s); err != nil {
            return nil, fmt.Errorf("applying option: %w", err)
        }
    }
    return s, nil
}
```

## Adapter Pattern

Bridge incompatible interfaces by wrapping one to satisfy another.

### Function Adapter

The standard library's `http.HandlerFunc` is the canonical example:

```go
type HandlerFunc func(ResponseWriter, *Request)

func (f HandlerFunc) ServeHTTP(w ResponseWriter, r *Request) {
    f(w, r)
}
```

Any function with the right signature becomes an `http.Handler` through the adapter.

### Structural Adapter

Wrap a third-party type to satisfy your internal interface:

```go
type Notifier interface {
    Notify(ctx context.Context, recipient string, message string) error
}

type slackAdapter struct {
    client *slack.Client
    channel string
}

func NewSlackNotifier(token string, channel string) Notifier {
    return &slackAdapter{
        client:  slack.New(token),
        channel: channel,
    }
}

func (s *slackAdapter) Notify(ctx context.Context, recipient string, message string) error {
    _, _, err := s.client.PostMessageContext(
        ctx,
        s.channel,
        slack.MsgOptionText(fmt.Sprintf("@%s: %s", recipient, message), false),
    )
    if err != nil {
        return fmt.Errorf("posting to slack: %w", err)
    }
    return nil
}
```

Your code depends on `Notifier`, not on `*slack.Client`. Switching to email, SMS, or a test stub requires only a new adapter.

### Reader Adapter

Adapt a custom data source to satisfy `io.Reader`:

```go
type channelReader struct {
    ch  <-chan []byte
    buf []byte
}

func NewChannelReader(ch <-chan []byte) io.Reader {
    return &channelReader{ch: ch}
}

func (r *channelReader) Read(p []byte) (int, error) {
    if len(r.buf) == 0 {
        data, ok := <-r.ch
        if !ok {
            return 0, io.EOF
        }
        r.buf = data
    }
    n := copy(p, r.buf)
    r.buf = r.buf[n:]
    return n, nil
}
```

Any function that accepts `io.Reader` can now read from a channel.

## Strategy Pattern

Define a family of algorithms as interface implementations. The consumer selects the strategy at runtime.

### Compression Strategy

```go
type Compressor interface {
    Compress(data []byte) ([]byte, error)
    Decompress(data []byte) ([]byte, error)
}

type gzipCompressor struct {
    level int
}

func NewGzipCompressor(level int) Compressor {
    return &gzipCompressor{level: level}
}

func (g *gzipCompressor) Compress(data []byte) ([]byte, error) {
    var buf bytes.Buffer
    w, err := gzip.NewWriterLevel(&buf, g.level)
    if err != nil {
        return nil, fmt.Errorf("creating gzip writer: %w", err)
    }
    if _, err := w.Write(data); err != nil {
        return nil, fmt.Errorf("writing gzip data: %w", err)
    }
    if err := w.Close(); err != nil {
        return nil, fmt.Errorf("closing gzip writer: %w", err)
    }
    return buf.Bytes(), nil
}

func (g *gzipCompressor) Decompress(data []byte) ([]byte, error) {
    r, err := gzip.NewReader(bytes.NewReader(data))
    if err != nil {
        return nil, fmt.Errorf("creating gzip reader: %w", err)
    }
    defer r.Close()
    return io.ReadAll(r)
}

type noopCompressor struct{}

func (noopCompressor) Compress(data []byte) ([]byte, error)   { return data, nil }
func (noopCompressor) Decompress(data []byte) ([]byte, error) { return data, nil }
```

### Using the Strategy

```go
type Archive struct {
    compressor Compressor
    storage    io.Writer
}

func NewArchive(storage io.Writer, compressor Compressor) *Archive {
    return &Archive{compressor: compressor, storage: storage}
}

func (a *Archive) Store(data []byte) error {
    compressed, err := a.compressor.Compress(data)
    if err != nil {
        return fmt.Errorf("compressing data: %w", err)
    }
    if _, err := a.storage.Write(compressed); err != nil {
        return fmt.Errorf("writing to storage: %w", err)
    }
    return nil
}
```

Swap strategies without changing the `Archive` code:

```go
archive := NewArchive(file, NewGzipCompressor(gzip.BestSpeed))
archive := NewArchive(file, noopCompressor{})
```

### Sorting Strategy

```go
type Sorter interface {
    Sort(data []int)
}

type quickSort struct{}

func (quickSort) Sort(data []int) {
    sort.Ints(data)
}

type stableSort struct{}

func (stableSort) Sort(data []int) {
    sort.Stable(sort.IntSlice(data))
}

type Pipeline struct {
    sorter Sorter
}

func (p *Pipeline) Process(data []int) []int {
    result := make([]int, len(data))
    copy(result, data)
    p.sorter.Sort(result)
    return result
}
```

## Pattern Selection Guide

| Need | Pattern | Key Signal |
|---|---|---|
| Add behavior without modifying existing code | Decorator | "I want logging/metrics/caching around X" |
| Cross-cutting concerns for HTTP | Middleware | Working with `http.Handler` chain |
| Flexible constructor with defaults | Functional Options | Many optional configuration parameters |
| Bridge incompatible APIs | Adapter | Third-party type does not satisfy your interface |
| Swap algorithms at runtime | Strategy | Multiple implementations of the same behavior, selected by configuration or context |
