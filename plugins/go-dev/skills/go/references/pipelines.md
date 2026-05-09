# Pipelines

## Generator Pattern

A generator returns a receive-only channel and launches a goroutine that produces values. The generator owns the channel and closes it when done.

```go
func generate(ctx context.Context, values ...int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for _, v := range values {
            select {
            case out <- v:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

Every generator must accept a `context.Context` and check `ctx.Done()` in its select to prevent goroutine leaks when the caller cancels.

## Pipeline Stages

A pipeline connects generators through transformation stages. Each stage receives from an input channel, processes values, and sends results on an output channel.

```go
func square(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for v := range in {
            select {
            case out <- v * v:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}

func filter(ctx context.Context, in <-chan int, predicate func(int) bool) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for v := range in {
            if !predicate(v) {
                continue
            }
            select {
            case out <- v:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

Composing a pipeline:

```go
func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()

    nums := generate(ctx, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
    squared := square(ctx, nums)
    evens := filter(ctx, squared, func(v int) bool { return v%2 == 0 })

    for v := range evens {
        fmt.Println(v)
    }
}
```

When the caller calls `cancel()`, every stage's `ctx.Done()` fires and goroutines exit. The `defer close(out)` propagates channel closure downstream.

## Fan-Out / Fan-In

### Fan-Out

Multiple goroutines read from the same channel. The Go runtime distributes values to whichever goroutine is ready.

```go
func fanOut(ctx context.Context, in <-chan Task, workers int) []<-chan Result {
    channels := make([]<-chan Result, workers)
    for i := range workers {
        channels[i] = processWorker(ctx, in, i)
    }
    return channels
}

func processWorker(ctx context.Context, in <-chan Task, id int) <-chan Result {
    out := make(chan Result)
    go func() {
        defer close(out)
        for task := range in {
            select {
            case out <- execute(task):
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

### Fan-In

Merges multiple channels into a single channel. The merged channel closes when all inputs are exhausted.

```go
func fanIn(ctx context.Context, channels ...<-chan Result) <-chan Result {
    out := make(chan Result)
    var wg sync.WaitGroup

    for _, ch := range channels {
        wg.Add(1)
        go func(c <-chan Result) {
            defer wg.Done()
            for v := range c {
                select {
                case out <- v:
                case <-ctx.Done():
                    return
                }
            }
        }(ch)
    }

    go func() {
        wg.Wait()
        close(out)
    }()

    return out
}
```

Usage:

```go
ctx, cancel := context.WithCancel(context.Background())
defer cancel()

tasks := generate(ctx, taskList...)
workerOutputs := fanOut(ctx, tasks, 4)
results := fanIn(ctx, workerOutputs...)

for r := range results {
    handleResult(r)
}
```

## Worker Pool with errgroup

The simplest worker pool uses `errgroup.SetLimit`. No manual channel plumbing required.

```go
func processAll(ctx context.Context, items []Item) error {
    g, ctx := errgroup.WithContext(ctx)
    g.SetLimit(10)

    for _, item := range items {
        g.Go(func() error {
            return processItem(ctx, item)
        })
    }

    return g.Wait()
}
```

This approach:
- Limits concurrency to 10 goroutines
- Cancels remaining work on first error (via `WithContext`)
- Returns the first error encountered
- Requires no channels, WaitGroups, or semaphores

### Worker Pool with Channel-Based Task Distribution

For long-running worker pools where tasks arrive over time (not a fixed slice), use a channel.

```go
func runWorkerPool(ctx context.Context, tasks <-chan Task, workers int) error {
    g, ctx := errgroup.WithContext(ctx)

    for range workers {
        g.Go(func() error {
            for {
                select {
                case task, ok := <-tasks:
                    if !ok {
                        return nil
                    }
                    if err := process(ctx, task); err != nil {
                        return fmt.Errorf("processing task %s: %w", task.ID, err)
                    }
                case <-ctx.Done():
                    return ctx.Err()
                }
            }
        })
    }

    return g.Wait()
}
```

## Bounded Concurrency with Semaphore

When you need bounded concurrency without errgroup, use a buffered channel as a semaphore.

```go
func processAllBounded(ctx context.Context, items []Item, maxConcurrency int) error {
    sem := make(chan struct{}, maxConcurrency)
    var (
        mu      sync.Mutex
        firstErr error
    )

    var wg sync.WaitGroup
    for _, item := range items {
        select {
        case sem <- struct{}{}:
        case <-ctx.Done():
            break
        }

        wg.Add(1)
        go func(it Item) {
            defer wg.Done()
            defer func() { <-sem }()

            if err := processItem(ctx, it); err != nil {
                mu.Lock()
                if firstErr == nil {
                    firstErr = err
                }
                mu.Unlock()
            }
        }(item)
    }

    wg.Wait()
    return firstErr
}
```

Prefer `errgroup.SetLimit` over manual semaphores. The manual approach is shown for cases where errgroup is not available or when you need custom backpressure behavior.

## Graceful Shutdown of Pipelines

A pipeline shuts down cleanly when:
1. The source stops producing (closes its output channel)
2. Each stage detects the closed input, finishes in-progress work, and closes its output
3. Context cancellation propagates to all stages for immediate shutdown

### Drain Pattern

When cancelling a pipeline, in-progress values may be buffered in channels. A drain goroutine prevents sender goroutines from blocking.

```go
func drainAndCancel(cancel context.CancelFunc, channels ...<-chan any) {
    cancel()
    for _, ch := range channels {
        go func(c <-chan any) {
            for range c {
            }
        }(ch)
    }
}
```

### Full Pipeline with Graceful Shutdown

```go
func runPipeline(ctx context.Context, input []string) ([]Result, error) {
    ctx, cancel := context.WithCancel(ctx)
    defer cancel()

    urls := generate(ctx, input...)
    fetched := fetchStage(ctx, urls, 5)
    parsed := parseStage(ctx, fetched)

    var results []Result
    for r := range parsed {
        if r.Err != nil {
            cancel()
            for range parsed {
            }
            return nil, fmt.Errorf("pipeline failed: %w", r.Err)
        }
        results = append(results, r)
    }

    return results, nil
}
```

On error:
1. `cancel()` signals all stages to stop via `ctx.Done()`
2. The drain loop (`for range parsed`) consumes remaining buffered values so upstream goroutines can unblock their sends and exit
3. Each stage's `defer close(out)` fires as its goroutine returns, propagating closure downstream

### Shutdown Ordering

1. Cancel the context (signals all goroutines)
2. Drain all intermediate channels (prevents goroutines blocking on send)
3. Wait for all goroutines to exit (WaitGroup or errgroup)
4. Close any external resources (database connections, file handles)

Never close a channel to signal shutdown. Closing is for indicating "no more values." Use context cancellation for shutdown signaling.
