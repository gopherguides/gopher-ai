# Generated Project CLAUDE.md Content Guide

Loaded on demand when creating the CLAUDE.md for a generated/converted project. Create a CLAUDE.md in the project root containing the following sections (adjust the project name):

**Critical Build Error Section:**

- ALWAYS check `./tmp/air-combined.log` after making code changes
- This log contains compilation errors, template generation errors, SQL generation errors
- Never assume code changes succeeded without checking this log

**Development Workflow Section:**

- Explain that `make dev` is always running during development
- It automatically: kills existing process, regenerates Templ, regenerates sqlc, runs go mod tidy, rebuilds and restarts
- Developer does NOT need to manually run: templ generate, sqlc generate, go build, air

**Environment Section:**

- All config via `.envrc` with direnv
- DATABASE_URL, PORT (default 3000), ENV, LOG_LEVEL

**Key Commands Table:**

- `make dev` - Start with hot reload (main workflow)
- `make build` - Build production binary
- `make test` - Run tests with race detection
- `make lint` - Run linters
- `make migrate` - Run database migrations
- `make css-watch` - Watch Tailwind (run in separate terminal)

**Project Structure Table:**

- cmd/server/ - Entry point
- internal/config/ - Environment config
- internal/database/ - Database and sqlc
- internal/handler/ - HTTP handlers
- internal/middleware/ - Echo middleware
- templates/ - Templ templates
- static/ - CSS, JS, images
- migrations/ - goose migrations
- sqlc/ - SQL queries

**Code Patterns:**

- Logging: Use slog (never fmt.Printf or log.Printf)
- Errors: Wrap with context using fmt.Errorf
- Database: Use sqlc-generated queries
- Templates: Use Templ components

