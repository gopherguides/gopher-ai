---
name: go-best-practices
description: "Idiomatic Go patterns and routing hub to specialized Go skills (interfaces, concurrency, testing, errors, profiling, organization). Trigger when user pastes Go code, asks 'is this idiomatic', 'how should I structure this', or any open Go question that doesn't fit a more specific child skill."
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

## When the Right Design Is Unclear: Generate Alternatives

For high-stakes design moments — interface shape, package boundary, error strategy, refactor sequence — a single first answer is usually weaker than the comparison between several. When the right shape is genuinely uncertain:

1. Spawn 3+ Agent sub-agents in **one message** (parallel, not sequential), each with a different hard constraint, e.g.:
   - Minimize surface area — fewest exported methods possible
   - Maximize flexibility — anticipate plausible future use cases
   - Optimize for the most common call site
   - Mimic the closest stdlib idiom

2. Each agent returns a concrete sketch: type signatures, one usage example, one paragraph on what it hides.

3. Compare in prose: which design has the deepest abstraction (small surface, significant hidden complexity), which makes correct use easiest, where designs diverge most.

4. The chosen design often combines elements from multiple sketches. The value is in the contrast, not in picking a single winner outright.

This is generation, not exploration — the sub-agents are producing competing answers, not investigating the codebase. Apply most often when designing interfaces (→ go-interfaces) and package boundaries (→ go-code-organization).

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
