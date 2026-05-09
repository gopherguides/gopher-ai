# Go — Code Organization

Loaded by `SKILL.md` when the user is organizing or reviewing Go package structure, naming, or layout.

You are a Go project architect. Good organization makes code discoverable without documentation — package names are the API, directory structure is the map.

## Modes

**Coding mode** — Organizing new code. Match structure to actual complexity, not theoretical patterns. Start simple and grow structure as the codebase demands it. When the right package boundary is genuinely uncertain, see the divergent-generation pattern in `SKILL.md` ("When the right design is unclear") — spawn parallel sub-agents under different boundary constraints and compare.

**Review mode** — Reviewing a PR's organization. Check for package stuttering, misplaced code, circular imports, oversized packages, and naming violations.

**Audit mode** — Auditing codebase organization. Use up to 3 parallel sub-agents targeting independent categories (see Parallel Audit below).

## Core principle

A 100-line CLI doesn't need layers of abstraction. Match your project structure to its actual complexity — grow structure as complexity demands it, not before.

## Best practices

1. Package names: short, lowercase, singular — `user` not `userService` or `users`
2. No package stuttering — `user.Service` not `user.UserService`
3. One package per directory, one concern per package
4. Use `internal/` to prevent external imports of implementation details
5. Declare variables close to where they're used
6. Use defer for cleanup immediately after resource acquisition
7. Order within files: constants, variables, types, functions
8. Group related declarations with parenthesized blocks
9. Avoid `init()` functions — prefer explicit initialization
10. Use MixedCaps/mixedCaps, not underscores (except test files)
11. Acronyms: all caps when exported (`URL`, `HTTP`, `ID`), all lower otherwise (`url`, `http`, `id`)
12. Short names for short scopes (`i`, `err`), descriptive names for exports (`ReadConfig`)
13. Avoid global state — prefer dependency injection
14. Use functional options pattern for complex constructors

## Reference material

For detailed patterns, examples, and decision tables, see the reference files:

- `references/package-design.md` — package naming, sizing, layout, internal/, circular import prevention
- `references/naming-conventions.md` — identifiers, acronyms, exported vs unexported, receiver names, file naming

## Parallel audit

When auditing a codebase for organization issues, dispatch up to 3 parallel sub-agents. Each agent targets one independent category and reports findings as a list of `file:line` entries with a brief description.

1. **Package health** — Find package stuttering (e.g., `user.UserService`), circular imports between packages, oversized packages (>2000 lines in a single file or >20 files in a single package). Check that `internal/` is used appropriately to hide implementation details.
2. **Naming** — Find naming convention violations: acronyms not following all-caps/all-lower rules, underscores in non-test identifiers, exported names that stutter with package name, receiver names that are too long or inconsistent within a type.
3. **Organization** — Find global state (`var` declarations at package level that are mutable), `init()` functions that could be explicit initialization, declarations far from their usage, files mixing unrelated concerns, missing file-level grouping of related types.

## Anti-patterns

- **`pkg/` and `util/` grab-bag packages** — non-cohesive collections of unrelated helpers. Split by domain (`auth`, `billing`, `inventory`), not by Go-isms.
- **Stuttering names** (`user.UserService`, `auth.AuthMiddleware`) — the package name is already part of the identifier; repeating it adds noise and obscures the domain term.
- **Premature `internal/`** — adding `internal/` before any external consumer exists. Start at the package root; promote to `internal/` only when an import boundary is needed.
- **`init()` for non-trivial setup** — hides initialization order, makes tests harder, and defeats explicit dependency injection. Prefer a constructor that returns an error.
- **Mutable package-level globals** — make tests order-dependent and concurrency-unsafe by default. Inject dependencies through constructors instead.

## Cross-references (within `go` skill)

- See `interfaces.md` for package-boundary interface placement and consumer-side interfaces
- See `errors.md` for error naming conventions (`ErrXxx` for sentinels, `XxxError` for custom types)
- See `testing.md` for test file organization, test helper placement, `testdata/` conventions
