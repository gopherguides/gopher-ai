# Channels and Select

## Unbuffered vs Buffered Channels

### Unbuffered Channels

An unbuffered channel synchronizes sender and receiver. The sender blocks until the receiver is ready, and vice versa. This provides a strong ordering guarantee.

```go
ch := make(chan int)

go func() {
    ch <- 42
}()

value := <-ch
```

Use unbuffered channels when:
- You need synchronization between goroutines (handoff semantics)
- The sender should not proceed until the receiver has the value
- You want backpressure — the producer waits for the consumer

### Buffered Channels

A buffered channel allows the sender to proceed without blocking until the buffer is full. The receiver blocks only when the buffer is empty.

```go
ch := make(chan int, 10)

ch <- 1
ch <- 2

value := <-ch
```

Use buffered channels when:
- You know the exact number of values to send (e.g., `make(chan result, len(tasks))`)
- Decoupling producer and consumer speeds where occasional bursts are expected
- Implementing a semaphore (`make(chan struct{}, maxConcurrency)`)

**Default to unbuffered.** Add a buffer only when you can justify the size. An arbitrary buffer (e.g., `make(chan int, 100)`) masks backpressure and delays deadlock detection.

## Channel Direction Types

Annotate channel parameters with direction to restrict usage at compile time.

```go
func producer(out chan<- int) {
    for i := 0; i < 10; i++ {
        out <- i
    }
    close(out)
}

func consumer(in <-chan int) {
    for v := range in {
        fmt.Println(v)
    }
}

func main() {
    ch := make(chan int)
    go producer(ch)
    consumer(ch)
}
```

- `chan<- T` — send-only. The function can send and close, but not receive.
- `<-chan T` — receive-only. The function can receive, but not send or close.
- `chan T` — bidirectional. Avoid in function signatures; prefer directional types.

A bidirectional channel implicitly converts to either directional type when passed to a function.

## Channel Ownership Rules

The goroutine that creates and sends on a channel owns it. The owner is responsible for closing it.

```go
func generate(ctx context.Context) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for i := 0; ; i++ {
            select {
            case out <- i:
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

Ownership rules:
1. The owner (sender) instantiates the channel
2. The owner writes values and closes when done
3. The owner passes the channel as `<-chan T` (receive-only) to consumers
4. Consumers never close the channel — they only read from it
5. Multiple consumers can safely read from the same channel (fan-out)
6. If multiple goroutines send on a channel, use `sync.Once` to coordinate closure

### Multiple Senders, One Close

When multiple senders share a channel, use a WaitGroup to close after all senders finish.

```go
func fanIn(ctx context.Context, sources ...func(context.Context, chan<- int)) <-chan int {
    out := make(chan int)
    var wg sync.WaitGroup
    for _, src := range sources {
        wg.Add(1)
        go func(s func(context.Context, chan<- int)) {
            defer wg.Done()
            s(ctx, out)
        }(src)
    }
    go func() {
        wg.Wait()
        close(out)
    }()
    return out
}
```

## Select Statement Patterns

### Basic Select

Select blocks until one of its cases can proceed. If multiple cases are ready, one is chosen at random.

```go
select {
case v := <-ch1:
    process(v)
case v := <-ch2:
    process(v)
case <-ctx.Done():
    return ctx.Err()
}
```

### Non-Blocking Send/Receive

Add a `default` case to make send or receive non-blocking.

```go
select {
case ch <- value:
case default:
    log.Println("channel full, dropping value")
}
```

```go
select {
case v := <-ch:
    process(v)
default:
}
```

### Timeout with Select

Use `time.NewTimer` for timeouts in loops. Never use `time.After` in a loop — it leaks a timer on every iteration.

```go
timer := time.NewTimer(5 * time.Second)
defer timer.Stop()

for {
    select {
    case v := <-ch:
        process(v)
        if !timer.Stop() {
            <-timer.C
        }
        timer.Reset(5 * time.Second)
    case <-timer.C:
        return fmt.Errorf("timed out waiting for value")
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

For a single wait (not in a loop), `time.After` is acceptable:

```go
select {
case v := <-ch:
    return v, nil
case <-time.After(5 * time.Second):
    return zero, fmt.Errorf("timed out")
case <-ctx.Done():
    return zero, ctx.Err()
}
```

### Priority Select

Go's select chooses randomly among ready cases. To prioritize one channel over another, use nested selects or a check-before-select pattern.

```go
for {
    select {
    case <-ctx.Done():
        return ctx.Err()
    default:
    }

    select {
    case v := <-highPriority:
        processHigh(v)
    case <-ctx.Done():
        return ctx.Err()
    default:
    }

    select {
    case v := <-highPriority:
        processHigh(v)
    case v := <-lowPriority:
        processLow(v)
    case <-ctx.Done():
        return ctx.Err()
    }
}
```

The outer `default` cases ensure context cancellation is checked first, and high-priority messages are drained before falling through to low-priority.

## Done Channel Pattern

A done channel signals goroutines to stop. It is closed (not sent on) to broadcast to all listeners.

```go
func worker(done <-chan struct{}, tasks <-chan Task) {
    for {
        select {
        case t, ok := <-tasks:
            if !ok {
                return
            }
            process(t)
        case <-done:
            return
        }
    }
}

func main() {
    done := make(chan struct{})
    tasks := make(chan Task, 10)

    var wg sync.WaitGroup
    for range 4 {
        wg.Add(1)
        go func() {
            defer wg.Done()
            worker(done, tasks)
        }()
    }

    close(done)
    wg.Wait()
}
```

In modern Go, prefer `context.Context` over a bare done channel. Context carries cancellation, deadlines, and values.

```go
func worker(ctx context.Context, tasks <-chan Task) {
    for {
        select {
        case t, ok := <-tasks:
            if !ok {
                return
            }
            process(t)
        case <-ctx.Done():
            return
        }
    }
}
```

## Or-Done Channel Pattern

Wraps a channel read so the caller does not need to check both the channel and a done signal in every select.

```go
func orDone(ctx context.Context, in <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for {
            select {
            case <-ctx.Done():
                return
            case v, ok := <-in:
                if !ok {
                    return
                }
                select {
                case out <- v:
                case <-ctx.Done():
                    return
                }
            }
        }
    }()
    return out
}
```

Usage simplifies downstream code:

```go
for v := range orDone(ctx, upstream) {
    process(v)
}
```

## Nil Channel Behavior

A nil channel blocks forever on both send and receive. This is useful for dynamically enabling or disabling select cases.

```go
func merge(ctx context.Context, ch1, ch2 <-chan int) <-chan int {
    out := make(chan int)
    go func() {
        defer close(out)
        for ch1 != nil || ch2 != nil {
            select {
            case v, ok := <-ch1:
                if !ok {
                    ch1 = nil
                    continue
                }
                out <- v
            case v, ok := <-ch2:
                if !ok {
                    ch2 = nil
                    continue
                }
                out <- v
            case <-ctx.Done():
                return
            }
        }
    }()
    return out
}
```

Setting a closed channel to nil removes it from the select, so the loop naturally exits when both inputs are exhausted.
