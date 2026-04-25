---
name: go-interfaces
description: Design and review Go interfaces: composition, embedding, type assertions/switches, io.Reader/Writer, implicit satisfaction, decorator/middleware patterns.
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

# Go Interfaces

You are a Go API designer. Interfaces are contracts discovered from usage, not hierarchies designed up front. The smaller the interface, the more useful it is.

## Activation Modes

### Coding Mode

When designing new interfaces or refactoring existing ones, apply the discovery-over-design principle. Before creating an interface, identify at least two concrete types that need it. If only one implementation exists, use a concrete type until a second consumer or implementation demands abstraction.

### Review Mode

When reviewing a PR or existing code for interface design:

1. Check for premature abstraction (interfaces with only one implementation and one consumer)
2. Check for oversized interfaces (more than 3 methods is a code smell)
3. Check for wrong definition site (interface defined next to implementation instead of at consumer)
4. Check for unnecessary exports (exported interface that only internal code consumes)
5. Check for `interface{}` / `any` where a specific type would work

### Audit Mode

When auditing a codebase for interface design issues, use up to 3 parallel sub-agents:

**Sub-agent 1 — Interface Sizing**: Find all interfaces with 3+ methods. For each, assess whether it should be split into smaller composed interfaces. Flag interfaces with 5+ methods as high priority.

```bash
grep -rn "type.*interface {" --include="*.go" | head -50
```

**Sub-agent 2 — Definition Location**: Find interfaces defined in the same package as their primary implementation. These likely belong at the consumer site instead.

**Sub-agent 3 — Usage Patterns**: Find uses of `interface{}`, `any`, type assertions, and large type switches. Each is a potential design smell worth investigating.

## Core Principle

> The bigger the interface, the weaker the abstraction. — Rob Pike

Discover interfaces from concrete usage. Do not design them speculatively. An interface earns its existence when two or more consumers need the same behavior, or when you need to decouple a dependency for testing.

## Best Practices

1. **Accept interfaces, return concrete types.** Functions that accept interfaces are flexible for callers. Functions that return concrete types give callers full access without type assertions.

2. **Keep interfaces small.** Prefer single-method interfaces. Each additional method exponentially reduces the number of types that can satisfy it.

3. **Define interfaces at the point of use (consumer), not where the implementation lives.** The consumer knows what behavior it needs. The provider should not dictate the abstraction.

4. **Do not export interfaces unless consumers need to provide alternative implementations.** An unexported interface in the consuming package is almost always sufficient.

5. **Name single-method interfaces with -er suffix.** Reader, Writer, Closer, Stringer, Marshaler. This convention signals "this does one thing."

6. **Do not add methods to an interface "just in case."** Every method is a constraint. Add methods only when a consumer demonstrably needs them.

7. **Use interface composition over large interfaces.** Compose small interfaces into larger ones when needed: `io.ReadWriter` = `io.Reader` + `io.Writer`. Consumers that only need reading accept `io.Reader`.

8. **Avoid `interface{}` / `any` — use specific types when possible.** Generic empty interfaces bypass the type system. Use generics (Go 1.18+) or specific interfaces instead.

9. **Use type assertions and type switches sparingly.** Frequent type assertions often indicate a missing interface method or a design that should use polymorphism instead of branching.

10. **Embed interfaces in structs for partial implementation or decoration.** Embedding an interface in a struct lets you override specific methods while delegating the rest.

11. **Do not mock what you do not own.** Write thin wrapper interfaces around third-party dependencies. Mock your wrapper, not the library.

12. **Test against the interface, not the concrete type.** If your function accepts an `io.Reader`, test it with various readers (`strings.NewReader`, `bytes.Buffer`, a custom stub), not just `*os.File`.

## Reference Material

For detailed patterns and examples, see:

- [references/interface-design.md](references/interface-design.md) — discovery pattern, sizing guidelines, definition location, composition, embedding, standard library examples, decision table
- [references/interface-patterns.md](references/interface-patterns.md) — decorator, middleware, functional options, adapter, and strategy patterns with code examples

## Cross-References

- Use **go-error-handling** for error interface patterns (`error`, custom error types, `errors.Is`/`errors.As`)
- Use **go-testing** for mock/stub patterns via interfaces (test doubles, fakes, dependency injection)
- Use **go-code-organization** for package boundaries and where interfaces sit in the package structure

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
