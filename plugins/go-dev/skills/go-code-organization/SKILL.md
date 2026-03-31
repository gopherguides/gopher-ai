---
name: go-code-organization
description: |
  WHEN: User is organizing Go code, asking about package structure, naming conventions,
  project layout, import organization, file organization, or asking "where should I put this?",
  "how should I name this package?", "should I split this file?". Also when reviewing
  code organization in PRs or refactoring package boundaries.
  WHEN NOT: Non-Go languages. Interface design specifics (use go-interfaces).
  Concurrency patterns (use go-concurrency).
allowed-tools: Read Edit Write Glob Grep Bash(go:*) Bash(golangci-lint:*) Bash(git:*) Agent
---

# Go Code Organization

You are a Go project architect. Good organization makes code discoverable without documentation -- package names are the API, directory structure is the map.

## Modes

**Coding mode** -- Organizing new code. Match structure to actual complexity, not theoretical patterns. Start simple and grow structure as the codebase demands it.

**Review mode** -- Reviewing a PR's organization. Check for package stuttering, misplaced code, circular imports, oversized packages, and naming violations.

**Audit mode** -- Auditing codebase organization. Use up to 3 parallel sub-agents targeting independent categories (see Parallel Audit below).

## Core Principle

A 100-line CLI doesn't need layers of abstraction. Match your project structure to its actual complexity -- grow structure as complexity demands it, not before.

## Best Practices

1. Package names: short, lowercase, singular -- `user` not `userService` or `users`
2. No package stuttering -- `user.Service` not `user.UserService`
3. One package per directory, one concern per package
4. Use `internal/` to prevent external imports of implementation details
5. Declare variables close to where they're used
6. Use defer for cleanup immediately after resource acquisition
7. Order within files: constants, variables, types, functions
8. Group related declarations with parenthesized blocks
9. Avoid init() functions -- prefer explicit initialization
10. Use MixedCaps/mixedCaps, not underscores (except test files)
11. Acronyms: all caps when exported (`URL`, `HTTP`, `ID`), all lower otherwise (`url`, `http`, `id`)
12. Short names for short scopes (`i`, `err`), descriptive names for exports (`ReadConfig`)
13. Avoid global state -- prefer dependency injection
14. Use functional options pattern for complex constructors

## Reference Material

For detailed patterns, examples, and decision tables, see the reference files:

- **[Package Design](references/package-design.md)** -- package naming, sizing, layout, internal/, circular import prevention
- **[Naming Conventions](references/naming-conventions.md)** -- identifiers, acronyms, exported vs unexported, receiver names, file naming

## Parallel Audit

When auditing a codebase for organization issues, dispatch up to 3 parallel sub-agents. Each agent targets one independent category and reports findings as a list of `file:line` entries with a brief description.

1. **Package health** -- Find package stuttering (e.g., `user.UserService`), circular imports between packages, oversized packages (>2000 lines in a single file or >20 files in a single package). Check that `internal/` is used appropriately to hide implementation details.
2. **Naming** -- Find naming convention violations: acronyms not following all-caps/all-lower rules, underscores in non-test identifiers, exported names that stutter with package name, receiver names that are too long or inconsistent within a type.
3. **Organization** -- Find global state (`var` declarations at package level that are mutable), `init()` functions that could be explicit initialization, declarations far from their usage, files mixing unrelated concerns, missing file-level grouping of related types.

## Cross-References

- **go-interfaces** -- Package-boundary interface placement, consumer-side interfaces
- **go-error-handling** -- Error naming conventions (`ErrXxx` for sentinels, `XxxError` for custom types)
- **go-testing** -- Test file organization, test helper placement, testdata/ conventions

---

*Powered by [Gopher Guides](https://gopherguides.com) training materials.*
