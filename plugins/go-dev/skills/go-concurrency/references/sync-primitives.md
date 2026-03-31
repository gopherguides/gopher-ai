# Sync Primitives

## sync.Mutex and sync.RWMutex

### sync.Mutex

Provides exclusive access to a shared resource. Only one goroutine holds the lock at a time.

```go
type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Increment() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

func (c *SafeCounter) Value() int {
    c.mu.Lock()
    defer c.mu.Unlock()
    return c.count
}
```

Best practices:
- Keep critical sections small — lock, do the work, unlock
- Never hold a mutex across I/O, network calls, or channel operations
- Always use `defer mu.Unlock()` to prevent forgetting to unlock on early returns
- Embed the mutex next to the fields it protects, not at the top of the struct
- Never copy a struct containing a mutex (use pointer receivers)

### sync.RWMutex

Allows multiple concurrent readers OR one exclusive writer. Use when reads vastly outnumber writes.

```go
type Cache struct {
    mu    sync.RWMutex
    items map[string]string
}

func (c *Cache) Get(key string) (string, bool) {
    c.mu.RLock()
    defer c.mu.RUnlock()
    v, ok := c.items[key]
    return v, ok
}

func (c *Cache) Set(key, value string) {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.items[key] = value
}
```

Use `sync.RWMutex` only when profiling shows read contention on a plain `Mutex`. The overhead of RWMutex is higher per operation, so it only wins when read concurrency is high.

## sync/atomic

Lock-free operations for simple values. Lower overhead than mutexes for counters and flags.

### Typed Atomics (Go 1.19+)

```go
var counter atomic.Int64

func increment() {
    counter.Add(1)
}

func value() int64 {
    return counter.Load()
}
```

Available types: `atomic.Bool`, `atomic.Int32`, `atomic.Int64`, `atomic.Uint32`, `atomic.Uint64`, `atomic.Pointer[T]`.

### atomic.Pointer[T] (Go 1.19+)

Type-safe atomic pointer operations without `unsafe.Pointer`.

```go
type Config struct {
    Timeout time.Duration
    MaxConn int
}

var currentConfig atomic.Pointer[Config]

func UpdateConfig(cfg *Config) {
    currentConfig.Store(cfg)
}

func GetConfig() *Config {
    return currentConfig.Load()
}
```

### atomic.Value

For storing arbitrary types atomically. Prefer typed atomics when the type is known.

```go
var config atomic.Value

func init() {
    config.Store(DefaultConfig())
}

func GetConfig() Config {
    return config.Load().(Config)
}
```

The stored type must be consistent — storing different types panics.

## sync.Map

A concurrent map optimized for two patterns: keys written once and read many times, or disjoint sets of keys per goroutine.

```go
var cache sync.Map

func Get(key string) (any, bool) {
    return cache.Load(key)
}

func Set(key string, value any) {
    cache.Store(key, value)
}

func GetOrCreate(key string, create func() any) any {
    v, loaded := cache.LoadOrStore(key, create())
    if !loaded {
        return v
    }
    return v
}
```

When to use `sync.Map` vs `RWMutex` + `map`:
- Use `sync.Map` when keys are stable (written once, read many) or when goroutines access disjoint key sets
- Use `RWMutex` + `map` when you need to iterate, the key set changes frequently, or you need typed values without assertion

## sync.Pool

Reuses temporary objects to reduce allocation pressure. Objects may be collected at any GC cycle.

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func Process(data []byte) string {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)

    buf.Write(data)
    return buf.String()
}
```

Best practices:
- Always `Reset` the object before `Put` to avoid leaking data between uses
- Never store pointers to pool objects — they may be collected
- Use for high-frequency, short-lived allocations (buffers, encoders, temporary structs)
- Profile first — `sync.Pool` adds complexity and only helps when allocation is a proven bottleneck

## sync.Once

Executes a function exactly once, regardless of how many goroutines call it. All callers block until the function completes.

```go
var (
    instance *Database
    once     sync.Once
)

func GetDatabase() *Database {
    once.Do(func() {
        instance = connectToDatabase()
    })
    return instance
}
```

### OnceFunc, OnceValue, OnceValues (Go 1.21+)

Cleaner alternatives that return closures.

```go
var getDB = sync.OnceValue(func() *Database {
    return connectToDatabase()
})

func handler(w http.ResponseWriter, r *http.Request) {
    db := getDB()
    db.Query(r.Context(), "SELECT 1")
}
```

```go
var loadConfig = sync.OnceValues(func() (*Config, error) {
    return parseConfig("config.yaml")
})

func main() {
    cfg, err := loadConfig()
    if err != nil {
        log.Fatal(err)
    }
    run(cfg)
}
```

`OnceFunc` wraps a `func()`, `OnceValue` wraps a `func() T`, `OnceValues` wraps a `func() (T, error)`. All panic on subsequent calls if the wrapped function panicked on first call.

## sync.WaitGroup

Waits for a collection of goroutines to finish.

```go
var wg sync.WaitGroup

for _, url := range urls {
    wg.Add(1)
    go func(u string) {
        defer wg.Done()
        fetch(u)
    }(url)
}

wg.Wait()
```

Critical rule: Call `wg.Add` before the `go` statement. Calling `Add` inside the goroutine races with `Wait`.

### WaitGroup.Go (Go 1.24+)

Combines `Add`, `go`, and `Done` into a single call.

```go
var wg sync.WaitGroup

for _, url := range urls {
    wg.Go(func() {
        fetch(url)
    })
}

wg.Wait()
```

`wg.Go` calls `Add(1)`, launches the goroutine, and defers `Done()` internally. This eliminates the common mistake of misplacing `Add`.

## x/sync/errgroup

Manages a group of goroutines with error propagation and optional context cancellation.

### Basic Usage

```go
g, ctx := errgroup.WithContext(ctx)

for _, url := range urls {
    g.Go(func() error {
        return fetch(ctx, url)
    })
}

if err := g.Wait(); err != nil {
    return fmt.Errorf("fetching urls: %w", err)
}
```

`Wait` returns the first non-nil error. When created with `WithContext`, the derived context is cancelled when any goroutine returns an error, signaling siblings to stop.

### Bounded Concurrency

```go
g, ctx := errgroup.WithContext(ctx)
g.SetLimit(10)

for _, task := range tasks {
    g.Go(func() error {
        return process(ctx, task)
    })
}

if err := g.Wait(); err != nil {
    return fmt.Errorf("processing tasks: %w", err)
}
```

`SetLimit(n)` restricts the number of goroutines running simultaneously. This replaces manual semaphore-with-buffered-channel patterns.

### TryGo for Non-Blocking Submission

```go
g.SetLimit(5)

for _, task := range tasks {
    if !g.TryGo(func() error {
        return process(ctx, task)
    }) {
        log.Printf("worker pool full, processing %s synchronously", task.ID)
        if err := process(ctx, task); err != nil {
            return err
        }
    }
}
```

## x/sync/singleflight

Deduplicates concurrent calls to the same function. Only one call executes; all others wait and receive the same result.

```go
var group singleflight.Group

func GetUser(ctx context.Context, id string) (*User, error) {
    v, err, shared := group.Do(id, func() (any, error) {
        return db.FetchUser(ctx, id)
    })
    if err != nil {
        return nil, fmt.Errorf("fetching user %s: %w", id, err)
    }
    user := v.(*User)
    if shared {
        log.Printf("singleflight: shared result for user %s", id)
    }
    return user, nil
}
```

Use singleflight when:
- Multiple goroutines request the same expensive resource simultaneously (cache stampede)
- You want to deduplicate concurrent database or API calls for the same key
- Building a cache where thundering herd is a concern

The `shared` return value indicates whether the result was shared with other callers. Use `DoChan` for non-blocking usage with channels.

```go
ch := group.DoChan(key, func() (any, error) {
    return expensiveCall()
})

select {
case result := <-ch:
    if result.Err != nil {
        return nil, result.Err
    }
    return result.Val.(*User), nil
case <-ctx.Done():
    return nil, ctx.Err()
}
```

`Forget(key)` removes a key from the in-flight map, allowing the next caller to start a new execution. Useful when you detect the in-flight call is stale.
