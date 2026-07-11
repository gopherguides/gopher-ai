# go-web Template Library

Shared file templates used by `/go-web:create-go-project` and `/go-web:convert-to-go-project`.
These files are loaded on demand — commands Read only the templates that match the user's
choices (database type, admin dashboard, Clerk, deployment target) and Write them to the
target path in the generated project.

## Placeholder Convention

| Placeholder | Replace with |
|-------------|--------------|
| `{{PROJECT_NAME}}` | The project name / Go module name (e.g. `my-app`). Used in module paths, import paths, binary names, env defaults. |
| `{{DATABASE_TYPE}}` | The goose dialect for the selected database: `postgres`, `sqlite3`, or `mysql`. Used only in `core/Makefile`. |

Everything else in a template is literal content — in particular, `${DATABASE_URL}` (sqlc env
substitution), `$(BINARY_NAME)` / `$$DATABASE_URL` (Makefile), and `${PORT:-3000}` (.air.toml)
are NOT placeholders and must be written verbatim.

Generated HTTP servers use a 5-second read-header timeout, 15-second read timeout,
30-second write timeout, 60-second idle timeout, and 10-second graceful-shutdown deadline.

Some template filenames drop the leading dot (`gitignore`, `envrc.*`, `air.toml`,
`golangci.yml`) so they stay inert inside this repo; the target paths below are authoritative.

**Note:** `core/Makefile` recipe lines are tab-indented. Preserve the tabs exactly when
writing the file — spaces break Make.

## Manifest

### core/ — always copied

| Template | Target in generated project |
|----------|-----------------------------|
| core/go.mod | `go.mod` (add DB driver + service SDK requires per selection) |
| core/gitignore | `.gitignore` |
| core/package.json | `package.json` |
| core/Makefile | `Makefile` (replace `{{DATABASE_TYPE}}`) |
| core/air.toml | `.air.toml` |
| core/golangci.yml | `.golangci.yml` |

### env/ — pick ONE .envrc variant per database

| Template | Target |
|----------|--------|
| env/envrc.example | `.envrc.example` (always) |
| env/envrc.sqlite | `.envrc` (SQLite projects) |
| env/envrc.postgres | `.envrc` (PostgreSQL projects) |
| env/envrc.mysql | `.envrc` (MySQL projects) |

### db/ — pick the variant matching the selected database

| Template | Target |
|----------|--------|
| db/sqlc.postgres.yaml / db/sqlc.sqlite.yaml / db/sqlc.mysql.yaml | `sqlc/sqlc.yaml` |
| db/queries-example.sql | `sqlc/queries/example.sql` (PostgreSQL `$1` params; adjust to `?` for SQLite/MySQL) |
| db/migration-initial.postgres.sql / .sqlite.sql / .mysql.sql | `internal/database/migrations/001_initial.sql` |
| db/database.postgres.go / db/database.sqlite.go / db/database.mysql.go | `internal/database/database.go` |

### app/ — common templates plus one database variant

| Template | Target |
|----------|--------|
| app/main.go | `cmd/server/main.go` |
| app/server.go | `cmd/server/server.go` |
| app/main_test.go | `cmd/server/main_test.go` |
| app/slog.go | `cmd/server/slog.go` |
| app/generate.go | `cmd/server/generate.go` |
| app/config.go | `internal/config/config.go` |
| app/ctxkeys.go | `internal/ctxkeys/keys.go` |
| app/meta.go | `internal/meta/meta.go` |
| app/meta-context.go | `internal/meta/context.go` |
| app/middleware.go | `internal/middleware/middleware.go` |
| app/handler.go | `internal/handler/handler.go` |
| app/home.go | `internal/handler/home.go` |
| app/testutil.<db>.go | `internal/testutil/testutil.go` (pick the variant matching the selected database) |

### templ/ — always copied (except the templUI snippet)

| Template | Target |
|----------|--------|
| templ/meta.templ | `templates/layouts/meta.templ` |
| templ/base.templ | `templates/layouts/base.templ` |
| templ/home.templ | `templates/pages/home.templ` |
| templ/base-templui-head.templ | SNIPPET — `<head>` changes to apply to `templates/layouts/base.templ` when templUI components are used (admin dashboard) |

### css/ — pick ONE

| Template | Target |
|----------|--------|
| css/input.css | `static/css/input.css` (no admin dashboard / no templUI) |
| css/input-templui.css | `static/css/input.css` (admin dashboard / templUI selected) |

### ci/ — copied unless the project already has CI

| Template | Target |
|----------|--------|
| ci/ci.yml | `.github/workflows/ci.yml` (keep only the `sqlc-vet` job variant for the selected database; delete the other two commented variants) |
| ci/dependabot.yml | `.github/dependabot.yml` |

### auth/ — only when Clerk is selected (see `references/clerk-integration.md`)

| Template | Target |
|----------|--------|
| auth/clerk.templ | `templates/components/clerk/clerk.templ` |
| auth/sign-in.templ | `templates/pages/sign-in.templ` |
| auth/sign-up.templ | `templates/pages/sign-up.templ` |
| auth/auth-handler.go | `internal/handler/auth.go` |
| auth/clerk-middleware.go | SNIPPET — Clerk middleware functions to add to `internal/middleware/` |

### deploy/ — only for the selected platform/build method (see `references/deployment/`)

| Template | Target |
|----------|--------|
| deploy/nixpacks.toml | `nixpacks.toml` (Nixpacks builds) |
| deploy/railway.toml | `railway.toml` (Railway only) |
| deploy/Dockerfile | `Dockerfile` (Dockerfile builds, required for Fly.io) |
| deploy/fly.toml | `fly.toml` (Fly.io only) |

### docs/

| Template | Target |
|----------|--------|
| docs/claude-md-guide.md | Content guide for the generated project's `CLAUDE.md` (not copied verbatim) |
