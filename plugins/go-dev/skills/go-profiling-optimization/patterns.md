# Go Optimization Patterns

Loaded by `SKILL.md` when the agent is about to apply a specific optimization.
Each pattern includes the slow-path and the fast-path so you can copy the right
shape directly into a fix.

## Preallocation

```go
// Avoid — grows slice multiple times, each grow allocates
items := []string{}
for _, v := range data {
    items = append(items, v)
}

// Good — allocate once with known capacity
items := make([]string, 0, len(data))
for _, v := range data {
    items = append(items, v)
}
```

## String Building

```go
// Avoid — each += allocates a new string
result := ""
for _, s := range parts {
    result += s
}

// Good — single allocation
var b strings.Builder
for _, s := range parts {
    b.WriteString(s)
}
result := b.String()
```

## Buffer Reuse

```go
// Avoid — allocates buffer every call
func readByte(r io.Reader) (byte, error) {
    var buf [1]byte
    _, err := r.Read(buf[:])
    return buf[0], err
}

// Good — caller provides reusable buffer
func readByte(r io.Reader, buf []byte) (byte, error) {
    _, err := r.Read(buf)
    return buf[0], err
}
```

## Buffered I/O

```go
// Avoid — each Read() call hits the OS
count := process(file)

// Good — bufio batches reads, dramatically fewer syscalls
br := bufio.NewReader(file)
count := process(br)
```

## sync.Pool for Frequent Allocations

```go
var bufPool = sync.Pool{
    New: func() any {
        return new(bytes.Buffer)
    },
}

func process() {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)
    // use buf...
}
```

CRITICAL: `sync.Pool` objects may be collected at any GC cycle. Never rely on pool for correctness — only for performance.

## Struct Field Alignment

```go
// Wastes memory — padding between fields
type Bad struct {
    a bool    // 1 byte + 7 padding
    b int64   // 8 bytes
    c bool    // 1 byte + 7 padding
}             // = 24 bytes

// Compact — fields ordered by size descending
type Good struct {
    b int64   // 8 bytes
    a bool    // 1 byte
    c bool    // 1 byte + 6 padding
}             // = 16 bytes
```

## Hot Path: Avoid Interface Boxing

```go
// Avoid in hot loops — each call boxes the int into interface{}
fmt.Sprintf("%d", n)

// Good — no interface boxing
strconv.Itoa(n)
```
