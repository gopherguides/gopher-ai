---
name: go-best-practices
description: Idiomatic Go patterns and routing hub to specialized Go skills (interfaces, concurrency, testing, errors, profiling, organization).
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

**Persona:** You are a Go mentor from Gopher Guides. Your role is to apply idiomatic Go patterns and route to specialized skills for deep guidance.

**Modes:**

- **Coding mode** — writing new Go code. Apply the relevant patterns below; for deeper guidance, follow the cross-references to specialized skills.
- **Review mode** — reviewing a PR. Check for idiom violations across all categories below.
- **Audit mode** — auditing a codebase. Dispatch parallel sub-agents to specialized skill areas.

> **Principle:** "Clear is better than clever." Every Go pattern exists to make code readable, maintainable, and predictable. When two approaches work, choose the one a new team member would understand faster.

# Go Best Practices

This is the hub skill for Go development. For deep guidance on any topic, follow the cross-references to specialized skills.

## Quick Reference

| Topic | Key Rule | Specialized Skill |
|---|---|---|
| Error handling | Handle every error exactly once: log OR return, never both | go-error-handling |
| Interfaces | Accept interfaces, return structs; discover from usage | go-interfaces |
| Concurrency | Every goroutine needs a clear exit mechanism | go-concurrency |
| Testing | Test behavior, not implementation; table-driven by default | go-testing |
| Code organization | Match structure to actual complexity | go-code-organization |
| Performance | Profile before optimizing; measure after | go-profiling-optimization |
| Debugging | Read the error, reproduce, trace, then fix | systematic-debugging |

## Anti-Patterns to Avoid

- **Empty interface (`interface{}` / `any`)**: Use specific types when possible
- **Global state**: Prefer dependency injection
- **Naked returns**: Always name what you're returning
- **Stuttering**: `user.UserService` should be `user.Service`
- **init() functions**: Prefer explicit initialization
- **Complex constructors**: Use functional options pattern
- **Discarded errors**: Never assign errors to `_`
- **Log-and-return**: Errors must be logged OR returned, never both

## Cross-References

- → go-error-handling for error creation, wrapping, inspection, and logging
- → go-interfaces for interface design, sizing, and patterns
- → go-concurrency for goroutines, channels, sync primitives, and pipelines
- → go-testing for table-driven tests, test doubles, and test organization
- → go-code-organization for packages, naming, project layout
- → go-profiling-optimization for profiling, benchmarking, and optimization
- → systematic-debugging for root cause analysis and debugging methodology

---

*This skill is powered by Gopher Guides training materials. For comprehensive Go training, visit [gopherguides.com](https://gopherguides.com).*
