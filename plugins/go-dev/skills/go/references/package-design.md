# Package Design in Go

## Overview

Package design is the single most impactful architectural decision in a Go codebase. Well-designed packages communicate intent through their names, enforce encapsulation through visibility rules, and prevent dependency tangles through clean import graphs.

## Package Naming Rules

Package names are the first thing consumers see. They form the prefix of every exported identifier, so they must be concise and descriptive.

### Rules

- **Short**: one word when possible (`http`, `user`, `config`)
- **Lowercase**: never MixedCaps or underscores (`httputil` not `httpUtil` or `http_util`)
- **Singular**: `user` not `users`, `model` not `models`
- **Descriptive of contents**: the name should tell you what the package provides
- **No utility names**: avoid `util`, `helper`, `common`, `misc`, `shared` -- these attract unrelated code

### Good vs Bad Package Names

```
Good: user, config, http, auth, store, migrate, render
Bad:  utils, helpers, common, models, types, shared, base
```

The `util` anti-pattern emerges when code has no clear home. The fix is to find the right package, not to create a dumping ground.

### Avoid Stuttering

The package name is part of every qualified reference. Stuttering happens when the exported name repeats the package name:

```go
// Stuttering -- the caller writes user.UserService
package user
type UserService struct{}

// Clean -- the caller writes user.Service
package user
type Service struct{}
```

```go
// Stuttering -- the caller writes config.ConfigReader
package config
func ConfigReader() {}

// Clean -- the caller writes config.Reader
package config
func Reader() {}
```

## Package Sizing

### When to Split a Package

Split when a package has multiple independent concerns that change for different reasons:

- A `user` package that handles both authentication and profile management should split into `auth` and `profile`
- A file exceeding 1000 lines is a signal (not a rule) that the package may have too many concerns
- A package with 20+ files likely needs subdivision

### When NOT to Split

Do not split prematurely:

- A package with 3 related types and 200 lines does not need subdivision
- Types that are always used together belong in the same package
- Splitting for the sake of "clean architecture" layers adds indirection without value

### The Right Size

A well-sized package:

- Has a name that describes all its contents without being vague
- Contains types and functions that are used together
- Can be understood by reading its exported API
- Does not require consumers to import multiple sub-packages for basic operations

## Project Layout

### Single File

For scripts, small tools, and learning exercises:

```
main.go
```

No packages, no directories. A `main.go` under 300 lines needs nothing else.

### Small CLI

For command-line tools with modest complexity:

```
main.go
config.go
run.go
```

Multiple files in `package main`. Split by concern, not by type. Each file handles one area of functionality.

### CLI with Library Code

When the tool has reusable logic:

```
cmd/
    myapp/
        main.go
main.go (or internal/)
config.go
store.go
```

The `cmd/` directory holds entry points. Library code lives at the root or in `internal/`.

### Web Service

A typical web service with clear domain boundaries:

```
cmd/
    server/
        main.go
internal/
    auth/
        auth.go
        middleware.go
    user/
        user.go
        store.go
    order/
        order.go
        store.go
http/
    handler.go
    middleware.go
    routes.go
store/
    postgres/
        user.go
        order.go
migrate/
    migrations/
        001_initial.sql
```

Domain packages (`auth`, `user`, `order`) define types and business logic. Infrastructure packages (`http`, `store`) handle I/O. The `internal/` directory prevents external consumers from depending on implementation details.

### Large System with Multiple Binaries

```
cmd/
    api/
        main.go
    worker/
        main.go
    migrate/
        main.go
internal/
    domain/
        user/
        order/
        payment/
    platform/
        postgres/
        redis/
        queue/
    service/
        checkout/
        notification/
```

Each binary in `cmd/` composes packages from `internal/`. Domain packages are pure business logic with no infrastructure dependencies. Platform packages wrap external systems. Service packages orchestrate domain and platform.

## The internal/ Directory

`internal/` is enforced by the Go toolchain. Code inside `internal/` can only be imported by code in the parent of `internal/`:

```
project/
    internal/
        auth/       <-- only importable by project/ and its children
    cmd/
        server/     <-- can import internal/auth
    pkg/
        client/     <-- can import internal/auth (same parent tree)
```

External consumers of the module cannot import anything under `internal/`.

### When to Use internal/

- Implementation details that should not be part of the public API
- Types and functions shared between packages within the module but not externally
- Domain logic that external consumers should not depend on directly

### When NOT to Use internal/

- Libraries intended for external consumption
- Types that callers need to use directly
- Do not put everything in `internal/` by default -- only use it when you need the import restriction

## Circular Import Prevention

Go does not allow circular imports. Package A cannot import B if B imports A (directly or transitively).

### Common Causes

1. **Two packages that define types referencing each other**: `user` imports `order` for `Order`, and `order` imports `user` for `User`
2. **A shared utility depending on domain packages**: `util` imports `user` for a helper, and `user` imports `util`
3. **Test packages importing the package under test through another path**

### Resolution Strategies

**Extract a shared types package:**

```
// Before: user imports order, order imports user
package user
import "myapp/order"
type User struct { Orders []order.Order }

package order
import "myapp/user"
type Order struct { Buyer user.User }

// After: both import a shared types package
package domain
type User struct { Orders []Order }
type Order struct { Buyer User }
```

**Use interfaces at the boundary:**

```go
// package order defines the interface it needs
package order

type UserLookup interface {
    FindByID(id string) (User, error)
}

// package user implements it without importing order
package user

func (s *Store) FindByID(id string) (User, error) { ... }
```

**Move the shared code to the lower-level package:**

If A and B both need a function, and A imports B, move the function into B (or extract it into a new package that both import).

**Dependency inversion:**

Higher-level packages define interfaces. Lower-level packages implement them. The composition happens in `main` or a wiring package.

## The cmd/ Pattern

Each subdirectory of `cmd/` is a separate `main` package producing one binary:

```
cmd/
    api/
        main.go       <-- builds "api" binary
    worker/
        main.go       <-- builds "worker" binary
    migrate/
        main.go       <-- builds "migrate" binary
```

Each `main.go` should be thin: parse flags, load config, wire dependencies, and call into library packages. Business logic does not belong in `cmd/`.

```go
package main

import (
    "log"
    "os"

    "myapp/internal/server"
    "myapp/internal/config"
)

func main() {
    cfg, err := config.Load(os.Args[1:])
    if err != nil {
        log.Fatal(err)
    }

    if err := server.Run(cfg); err != nil {
        log.Fatal(err)
    }
}
```

## Import Organization

Group imports into three blocks separated by blank lines:

```go
import (
    "context"
    "fmt"
    "net/http"

    "github.com/gorilla/mux"
    "go.uber.org/zap"

    "myapp/internal/auth"
    "myapp/internal/user"
)
```

1. Standard library
2. External dependencies
3. Internal/project packages

Use `goimports` to automate this. Configure your editor to run it on save.

## Vendor Directory

The `vendor/` directory stores a copy of all dependencies. It is created with `go mod vendor` and used when building with `-mod=vendor`.

### When to Vendor

- Reproducible builds without network access
- CI environments where you want hermetic builds
- Projects that need to audit all dependency source code

### When NOT to Vendor

- Most projects rely on the module cache and do not need `vendor/`
- Vendoring adds repository size and noise in code review
- The module proxy (`GOPROXY`) already provides availability guarantees

## go.mod Management

- Run `go mod tidy` before committing to remove unused dependencies and add missing ones
- Pin major versions explicitly in `go.mod` when upgrading
- Use `go mod graph` to understand the dependency tree
- Use `go mod why` to find out why a specific dependency exists
