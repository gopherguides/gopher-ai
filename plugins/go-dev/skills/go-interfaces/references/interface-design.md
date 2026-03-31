# Interface Design in Go

## Discovery Over Design

Go interfaces are satisfied implicitly. A type implements an interface by having the right methods, not by declaring intent. This means interfaces are discovered from usage patterns, not designed as type hierarchies.

The workflow:

1. Write concrete types first
2. Notice two or more consumers need the same behavior
3. Extract the minimal interface that captures that shared behavior
4. Define the interface at the consumer, not the provider

If you start by designing an interface before any concrete type exists, you are guessing. Guesses produce bloated interfaces that constrain future implementations unnecessarily.

### Before (Speculative Design)

```go
package storage

type Store interface {
    Get(key string) ([]byte, error)
    Set(key string, value []byte) error
    Delete(key string) error
    List(prefix string) ([]string, error)
    Watch(prefix string) (<-chan Event, error)
    Close() error
}
```

This interface has six methods. Any new implementation must implement all six, even if Watch is irrelevant for that backend. Every consumer depends on all six methods, even if it only calls Get.

### After (Discovered from Usage)

```go
package cache

type Getter interface {
    Get(key string) ([]byte, error)
}

func LoadThrough(g Getter, key string) ([]byte, error) {
    data, err := g.Get(key)
    if err != nil {
        return nil, fmt.Errorf("loading %s: %w", key, err)
    }
    return data, nil
}
```

```go
package cleanup

type Deleter interface {
    Delete(key string) error
}

func PurgeExpired(d Deleter, keys []string) error {
    for _, k := range keys {
        if err := d.Delete(k); err != nil {
            return fmt.Errorf("purging %s: %w", k, err)
        }
    }
    return nil
}
```

Each consumer defines only the behavior it needs. Any type with a `Get` method satisfies `cache.Getter`. Any type with a `Delete` method satisfies `cleanup.Deleter`. A single concrete type can satisfy both without knowing either interface exists.

## Interface Sizing Guidelines

| Method Count | Assessment | Action |
|---|---|---|
| 1 | Ideal | Single-responsibility, maximum reuse |
| 2 | Good | Acceptable when methods are inherently paired (Read + Close) |
| 3 | Review | Ask: can this be split into composed smaller interfaces? |
| 4-5 | Suspect | Almost certainly too large — split it |
| 6+ | Refactor | This is a type hierarchy disguised as an interface |

### The Splitting Test

For any interface with 3+ methods, ask:

- Do all consumers use all methods?
- Can I compose smaller interfaces to get the same result?
- Would removing one method make the interface usable by more types?

If any answer is yes, split.

```go
type ReadCloser interface {
    Reader
    Closer
}
```

Consumers that only read accept `Reader`. Consumers that need cleanup accept `ReadCloser`. The composed interface costs nothing extra but gives consumers exactly what they need.

## Where to Define Interfaces

### Rule: Define at the Consumer

The consumer knows what behavior it needs. The provider knows how to implement behavior but should not dictate which subset callers will use.

```go
package orders

type PaymentProcessor interface {
    Charge(amount int, currency string) (string, error)
}

type Service struct {
    payments PaymentProcessor
}

func (s *Service) PlaceOrder(cart Cart) error {
    txID, err := s.payments.Charge(cart.Total(), "USD")
    if err != nil {
        return fmt.Errorf("charging payment: %w", err)
    }
    cart.TransactionID = txID
    return nil
}
```

The `orders` package defines `PaymentProcessor` with exactly the one method it needs. The `payments` package provides a concrete `StripeClient` that has Charge plus Refund, ListTransactions, and other methods. The orders package never sees those extra methods.

### Exception: Exported Interfaces

Export an interface from the provider package when:

- The interface IS the product (like `io.Reader` in the standard library)
- Multiple packages need the exact same contract and defining it once prevents drift
- You are building a plugin system where third parties must implement the contract

Even in these cases, keep the interface minimal.

## Interface Composition

Build larger interfaces from smaller ones. Never start large and try to break down later.

```go
type Reader interface {
    Read(p []byte) (n int, err error)
}

type Writer interface {
    Write(p []byte) (n int, err error)
}

type Closer interface {
    Close() error
}

type ReadWriter interface {
    Reader
    Writer
}

type ReadWriteCloser interface {
    Reader
    Writer
    Closer
}
```

Consumers pick the smallest interface that covers their needs:

- Copy data: accept `Reader` and `Writer` separately
- Manage a resource lifecycle: accept `ReadWriteCloser`
- Just read: accept `Reader`

## Embedding Interfaces in Structs

Embedding an interface in a struct provides a default implementation that can be selectively overridden. This is the decorator and partial implementation pattern.

```go
type CountingWriter struct {
    io.Writer
    BytesWritten int64
}

func (cw *CountingWriter) Write(p []byte) (int, error) {
    n, err := cw.Writer.Write(p)
    cw.BytesWritten += int64(n)
    return n, err
}
```

`CountingWriter` delegates all `io.Writer` behavior to the embedded writer, but intercepts `Write` to count bytes. Any method on `io.Writer` that `CountingWriter` does not override is forwarded automatically.

IMPORTANT: If the embedded interface has methods you do not override, calling those methods on a nil embedded value will panic. Always initialize the embedded interface.

## Standard Library Interface Examples

These interfaces demonstrate the principles in action:

| Interface | Package | Methods | Why It Works |
|---|---|---|---|
| `io.Reader` | io | 1 | Satisfied by files, network connections, strings, buffers, compressors |
| `io.Writer` | io | 1 | Satisfied by files, network connections, buffers, hash functions |
| `fmt.Stringer` | fmt | 1 | Any type with `String() string` gets automatic formatting |
| `error` | builtin | 1 | The most widely implemented interface in Go |
| `sort.Interface` | sort | 3 | Minimum needed: length, comparison, swap |
| `http.Handler` | net/http | 1 | Entire HTTP middleware ecosystem built on one method |
| `encoding.TextMarshaler` | encoding | 1 | Custom text serialization for any type |
| `io.ReadWriteCloser` | io | 3 | Composed from three single-method interfaces |

Notice: the most powerful and widely used interfaces have one method. `sort.Interface` has three because sorting fundamentally requires all three operations.

## Decision Table: When to Create an Interface

| Situation | Create Interface? | Reasoning |
|---|---|---|
| Only one implementation exists, one consumer | No | Use the concrete type directly |
| Only one implementation, but you need to test the consumer | Yes | Define at consumer for test doubles |
| Two implementations, one consumer | Maybe | If the consumer is the only thing switching, a concrete type with a factory might suffice |
| One implementation, multiple consumers needing different subsets | Yes | Each consumer gets its own minimal interface |
| Multiple implementations, multiple consumers | Yes | This is what interfaces are for |
| Wrapping a third-party dependency | Yes | Thin interface at consumer for decoupling and testing |
| Building a plugin/extension system | Yes | Export the interface as the contract |
| "I might need this later" | No | YAGNI — add the interface when you actually need it |

The default answer is "no." Interfaces earn their place through demonstrated need, not anticipated need.
