---
argument-hint: "<project-name>"
description: "Create a new Go web project with Templ, HTMX, Alpine.js, Tailwind, and sqlc"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Create Go Project

**If `$ARGUMENTS` is empty or not provided:**

Display usage information and ask for input:

This command creates a production-ready Go web application with:

- **Echo v4** - Fast, minimalist web framework
- **Templ** - Type-safe HTML templates (compiles to Go)
- **Tailwind CSS v4** - Utility-first CSS framework
- **HTMX** - Server-driven interactivity via HTML attributes
- **Alpine.js** - Client-side interactivity (dropdowns, modals, tabs) without heavy JavaScript
- **sqlc** - Type-safe database queries from SQL
- **goose** - Database migrations
- **Air** - Hot reload for development

**Usage:** `/create-go-project <project-name>`

**Example:** `/create-go-project my-app`

**Workflow:**

1. Ask database preference (PostgreSQL, SQLite, MySQL)
2. Ask about optional services (authentication, email, payments)
3. Ask about admin dashboard (dark/light mode, sidebar)
4. Ask about deployment platform
5. Create project structure with all files
6. Initialize git repository
7. Provide next steps

Ask the user: "What would you like to name your project?"

---

**If `$ARGUMENTS` is provided:**

Create a new Go project named `$ARGUMENTS`. Follow this interactive flow:

## Step 1: Gather Project Requirements

<default_deployment_choice>
When the user hasn't expressed a strong preference, default to recommending **Vercel + Neon PostgreSQL**
as the deployment stack. This combination offers:

- Completely free tier for most projects
- Zero server management
- Automatic deployments from GitHub
- Production-ready from day one

Only suggest Railway, Fly.io, or self-hosted if the user:

- Explicitly requests it
- Needs SQLite in production
- Has specific requirements that Vercel can't meet
</default_deployment_choice>

Use AskUserQuestion to ask the following questions. Present them one at a time.

### Database Selection

Ask the user which database they want to use:

| Database | Best For |
|----------|----------|
| **PostgreSQL** (recommended) | Production apps, complex queries. Requires server (Neon, Supabase, or local) |
| **SQLite** | Prototypes, single-user apps. Just a file - no server needed |
| **MySQL** | Existing MySQL infrastructure |

**Plain explanations for beginners:**

- **PostgreSQL**: The "professional" choice used by most startups. Excellent for complex
  data and scales well. You'll need PostgreSQL installed locally or use a cloud service
  like Neon (free tier), Supabase, or Railway.

- **SQLite**: Perfect for getting started quickly. Your database is just a single file -
  no server needed. Great for prototypes and learning, but has limitations with multiple
  users accessing at once.

- **MySQL**: Choose this if your company already uses MySQL or you're migrating from
  PHP/WordPress. Similar capabilities to PostgreSQL.

### Optional Services

Ask the user which services to include (multi-select allowed):

| Service | Purpose |
|---------|---------|
| **Clerk** | User login/signup, password reset, sessions |
| **Brevo** | Send emails (welcome, notifications, password reset) |
| **Stripe** | Accept payments (credit cards, subscriptions) |
| **None** | Skip - add services later |

**Plain explanations for beginners:**

- **Clerk**: Handles user accounts so you don't build login forms, password reset,
  and email verification yourself. They handle security - you focus on your app.
  Free tier is generous. Visit <https://clerk.com>

- **Brevo** (formerly Sendinblue): When your app needs to send emails - welcome
  messages, password resets, notifications. They handle deliverability so your
  emails don't end up in spam. Free tier: 300 emails/day. Visit <https://brevo.com>

- **Stripe**: For accepting payments - credit cards, subscriptions, invoices.
  They handle compliance (PCI-DSS) so you never touch card numbers directly.
  You only pay when you make money. Visit <https://stripe.com>

### Admin Dashboard

Ask the user if they want an admin dashboard:

| Option | Description |
|--------|-------------|
| **Yes** (recommended) | Include admin UI with dark/light mode, sidebar, stats cards |
| **No** | Skip admin UI - build API or simple pages only |

The admin dashboard includes:

- Dark/light mode toggle with localStorage persistence
- Collapsible sidebar navigation
- Stats cards with icons
- Responsive mobile navigation
- TemplUI component integration

### Deployment Platform

Ask the user where they plan to deploy:

| Platform | When to Use | Cost |
|----------|-------------|------|
| **Vercel + Neon** | Default choice for most projects | Free tier |
| **Railway** | Need SQLite or traditional server | $5/mo credit |
| **Fly.io** | Need global edge or SQLite | Limited free |
| **Self-hosted** | Full control required | You manage |

**Why Vercel + Neon is the default:**

For most new Go projects, we recommend Vercel + Neon PostgreSQL because:

1. Both have generous free tiers (no credit card required)
2. GitHub integration means automatic deployments
3. No server management - focus on your code
4. Professional production setup from the start

If you're prototyping locally with SQLite and want to keep it simple,
Railway or Fly.io are better choices since they support persistent volumes.

**Plain explanations for beginners:**

- **Vercel + Neon**: Completely free for most projects. Connect your GitHub repo
  and it auto-deploys. 100,000 free requests/month. Neon provides free PostgreSQL.
  This is the recommended free hosting stack for production apps.

- **Railway**: Like Heroku but modern. Your app runs as a traditional server (same
  as local development). $5/month credit usually covers small projects for free.
  Good choice for SQLite or if you want a traditional server setup.

- **Fly.io**: Runs your app in multiple locations worldwide for faster access.
  More setup required (Docker helps) but great for global users. Works well with
  SQLite (persistent volumes) or any database.

- **Self-hosted**: You manage the server yourself. More work but full control.
  Best for SQLite production deployments.

**Example recommendation flow:**

- User: "Where should I deploy?" → Default to Vercel + Neon
- User chose SQLite earlier → Recommend Railway or Fly.io
- User: "I need to self-host" → Provide self-hosted guidance

---

## Step 2: Create Project Structure

After gathering requirements, create the project at `./$ARGUMENTS/`.

### Core Files

Create these files in order (dependencies matter):

#### 1. go.mod

```go
module $ARGUMENTS

go 1.25

require (
    github.com/labstack/echo/v4 v4.14.0
    github.com/a-h/templ v0.3.960
    github.com/lmittmann/tint v1.1.2
    // Database driver added based on selection
    // Service SDKs added based on selection
)
```

**Database-specific additions:**

- PostgreSQL: `github.com/jackc/pgx/v5`, `github.com/google/uuid`
- SQLite: `modernc.org/sqlite` (CGO-free, pure Go)
- MySQL: `github.com/go-sql-driver/mysql`

#### 2. .gitignore

```text
# Binaries
$ARGUMENTS
*.exe

# Build artifacts
tmp/
*.log

# Environment (never commit secrets)
.envrc
.env

# Generated files (can be regenerated)
*_templ.go
internal/database/sqlc/

# Dependencies
node_modules/

# IDE
.idea/
.vscode/
*.swp

# OS
.DS_Store
Thumbs.db

# Tailwind output (generated)
static/css/output.css
```

#### 3. .envrc.example

```bash
# Copy this file to .envrc and edit with your values
# Then run: direnv allow

# Database
# PostgreSQL: postgres://user:pass@localhost:5432/dbname?sslmode=disable
# SQLite: ./data/$ARGUMENTS.db
# MySQL: user:pass@tcp(localhost:3306)/dbname
export DATABASE_URL="YOUR_DATABASE_URL_HERE"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO (used for meta tags, OG, etc.)
export SITE_NAME="$ARGUMENTS"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"

# CLERK_SECRET_KEY and CLERK_PUBLISHABLE_KEY if Clerk selected
# BREVO_API_KEY if Brevo selected
# STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY, STRIPE_WEBHOOK_SECRET if Stripe selected
```

#### 4. package.json

```json
{
  "name": "$ARGUMENTS",
  "private": true,
  "scripts": {
    "css": "npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --minify",
    "css:watch": "npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --watch"
  },
  "devDependencies": {
    "tailwindcss": "^4.0.0",
    "@tailwindcss/cli": "^4.0.0"
  }
}
```

#### 5. Makefile

Create a comprehensive Makefile:

```makefile
SHELL := /bin/bash

.PHONY: dev build test lint generate css css-watch migrate migrate-down migrate-status migrate-create setup clean run help

BINARY_NAME=$ARGUMENTS
MIGRATIONS_DIR=migrations

dev:
    @if [ -f tmp/air-combined.log ]; then \
        mv tmp/air-combined.log tmp/air-combined-$$(date +%Y%m%d-%H%M%S).log; \
    fi
    @ls -t tmp/air-combined-*.log 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
    @air 2>&1 | tee tmp/air-combined.log

build: generate css
    go build -o $(BINARY_NAME) ./cmd/server

test:
    go test -v -race ./...

lint:
    golangci-lint run
    templ fmt templates/

generate:
    templ generate
    sqlc generate -f sqlc/sqlc.yaml

css:
    npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --minify

css-watch:
    npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --watch

# Database migration commands vary by database type
# PostgreSQL: goose -dir $(MIGRATIONS_DIR) postgres "$$DATABASE_URL" up
# SQLite: goose -dir $(MIGRATIONS_DIR) sqlite3 "$$DATABASE_URL" up
# MySQL: goose -dir $(MIGRATIONS_DIR) mysql "$$DATABASE_URL" up
migrate:
    goose -dir $(MIGRATIONS_DIR) DATABASE_TYPE "$$DATABASE_URL" up

migrate-down:
    goose -dir $(MIGRATIONS_DIR) DATABASE_TYPE "$$DATABASE_URL" down

migrate-status:
    goose -dir $(MIGRATIONS_DIR) DATABASE_TYPE "$$DATABASE_URL" status

migrate-create:
ifndef NAME
    $(error NAME is required. Usage: make migrate-create NAME=create_users)
endif
    goose -dir $(MIGRATIONS_DIR) create $(NAME) sql

setup:
    go install github.com/air-verse/air@latest
    go install github.com/a-h/templ/cmd/templ@latest
    go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
    go install github.com/pressly/goose/v3/cmd/goose@latest
    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest

clean:
    rm -f $(BINARY_NAME)
    rm -rf tmp/
    rm -f static/css/output.css

run: build
    ./$(BINARY_NAME)

help:
    @echo "Available targets:"
    @echo "  dev            - Run with Air hot reload"
    @echo "  build          - Build the binary"
    @echo "  test           - Run tests"
    @echo "  lint           - Run golangci-lint and templ fmt"
    @echo "  generate       - Generate templ and sqlc code"
    @echo "  css            - Build Tailwind CSS"
    @echo "  css-watch      - Watch and rebuild Tailwind CSS"
    @echo "  migrate        - Run database migrations"
    @echo "  migrate-down   - Rollback last migration"
    @echo "  migrate-status - Show migration status"
    @echo "  migrate-create - Create new migration (NAME=xxx)"
    @echo "  setup          - Install development tools"
    @echo "  clean          - Remove build artifacts"
    @echo "  run            - Build and run the server"
```

Replace `DATABASE_TYPE` with `postgres`, `sqlite3`, or `mysql` based on selection.

#### 6. .air.toml

```toml
root = "."
testdata_dir = "testdata"
tmp_dir = "tmp"

[build]
  args_bin = []
  bin = "./tmp/$ARGUMENTS"
  cmd = "go build -o ./tmp/$ARGUMENTS ./cmd/server"
  delay = 1000
  exclude_dir = ["assets", "tmp", "vendor", "testdata", "node_modules", "static", "internal/database/sqlc"]
  exclude_file = ["go.sum"]
  exclude_regex = ["_test.go", "_templ\\.go$"]
  exclude_unchanged = false
  follow_symlink = false
  full_bin = ""
  include_dir = []
  include_ext = ["go", "tpl", "tmpl", "html", "templ", "css"]
  include_file = []
  kill_delay = "2s"
  log = "build-errors.log"
  poll = false
  poll_interval = 0
  post_cmd = []
  pre_cmd = [
    "lsof -ti:${PORT:-3000} | xargs kill -9 2>/dev/null || true; sleep 0.5",
    "templ generate",
    "sqlc generate -f sqlc/sqlc.yaml",
    "go mod tidy"
  ]
  rerun = false
  rerun_delay = 500
  send_interrupt = false
  stop_on_error = false

[color]
  app = ""
  build = "yellow"
  main = "magenta"
  runner = "green"
  watcher = "cyan"

[log]
  main_only = false
  time = false

[misc]
  clean_on_exit = false

[proxy]
  app_port = 0
  enabled = false
  proxy_port = 0

[screen]
  clear_on_rebuild = false
  keep_scroll = true
```

#### 7. sqlc/sqlc.yaml

**For PostgreSQL:**

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "queries/"
    schema: "../migrations/"
    gen:
      go:
        package: "sqlc"
        out: "../internal/database/sqlc"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_empty_slices: true
        emit_pointers_for_null_types: true
        overrides:
          - db_type: "uuid"
            go_type:
              import: "github.com/google/uuid"
              type: "UUID"
          - db_type: "timestamptz"
            go_type: "time.Time"
```

**For SQLite:**

```yaml
version: "2"
sql:
  - engine: "sqlite"
    queries: "queries/"
    schema: "../migrations/"
    gen:
      go:
        package: "sqlc"
        out: "../internal/database/sqlc"
        emit_json_tags: true
        emit_empty_slices: true
```

**For MySQL:**

```yaml
version: "2"
sql:
  - engine: "mysql"
    queries: "queries/"
    schema: "../migrations/"
    gen:
      go:
        package: "sqlc"
        out: "../internal/database/sqlc"
        emit_json_tags: true
        emit_empty_slices: true
```

#### 8. sqlc/queries/example.sql

```sql
-- name: GetExample :one
SELECT * FROM examples WHERE id = $1 LIMIT 1;

-- name: ListExamples :many
SELECT * FROM examples ORDER BY created_at DESC LIMIT $1 OFFSET $2;

-- name: CreateExample :one
INSERT INTO examples (name, description) VALUES ($1, $2) RETURNING *;

-- name: UpdateExample :exec
UPDATE examples SET name = $1, description = $2, updated_at = NOW() WHERE id = $3;

-- name: DeleteExample :exec
DELETE FROM examples WHERE id = $1;
```

Adjust SQL syntax for SQLite (`?` params) or MySQL as needed.

#### 9. migrations/001_initial.sql

**For PostgreSQL:**

```sql
-- +goose Up
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE examples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- +goose Down
DROP TABLE IF EXISTS examples;
```

**For SQLite:**

```sql
-- +goose Up
CREATE TABLE examples (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- +goose Down
DROP TABLE IF EXISTS examples;
```

**For MySQL:**

```sql
-- +goose Up
CREATE TABLE examples (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- +goose Down
DROP TABLE IF EXISTS examples;
```

### Go Application Files

#### 10. cmd/server/slog.go

```go
package main

import (
    "log/slog"
    "os"
    "strings"
    "time"

    "github.com/lmittmann/tint"
)

func init() {
    level := getLogLevel()
    isDev := strings.ToLower(os.Getenv("ENV")) == "development"

    var handler slog.Handler
    if isDev {
        handler = tint.NewHandler(os.Stderr, &tint.Options{
            Level:      level,
            TimeFormat: time.Kitchen,
            AddSource:  level == slog.LevelDebug,
        })
    } else {
        handler = slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
            Level:     level,
            AddSource: false,
        })
    }

    slog.SetDefault(slog.New(handler))
}

func getLogLevel() slog.Level {
    switch strings.ToUpper(os.Getenv("LOG_LEVEL")) {
    case "DEBUG":
        return slog.LevelDebug
    case "WARN":
        return slog.LevelWarn
    case "ERROR":
        return slog.LevelError
    default:
        return slog.LevelInfo
    }
}
```

#### 11. cmd/server/main.go

```go
package main

import (
    "context"
    "log/slog"
    "os"
    "os/signal"
    "syscall"
    "time"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/database"
    "$ARGUMENTS/internal/handler"
    "$ARGUMENTS/internal/middleware"

    "github.com/labstack/echo/v4"
)

func main() {
    cfg := config.Load()

    ctx := context.Background()
    db, err := database.New(ctx, cfg.DatabaseURL)
    if err != nil {
        slog.Error("failed to connect to database", "error", err)
        os.Exit(1)
    }
    defer db.Close()

    e := echo.New()
    e.HideBanner = true
    e.HidePort = true

    middleware.Setup(e, cfg)

    h := handler.New(cfg, db)
    h.RegisterRoutes(e)

    go func() {
        addr := ":" + cfg.Port
        slog.Info("starting server", "port", cfg.Port, "env", cfg.Env)
        if err := e.Start(addr); err != nil {
            slog.Info("shutting down server")
        }
    }()

    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    if err := e.Shutdown(ctx); err != nil {
        slog.Error("server shutdown error", "error", err)
    }

    slog.Info("server stopped")
}
```

#### 12. internal/config/config.go

```go
package config

import (
    "log/slog"
    "os"
)

type SiteConfig struct {
    Name           string
    URL            string
    DefaultOGImage string
}

type Config struct {
    DatabaseURL string
    Port        string
    Env         string
    Site        SiteConfig
    // Add service keys based on selection:
    // ClerkSecretKey      string
    // ClerkPublishableKey string
    // BrevoAPIKey         string
    // StripeSecretKey     string
    // StripePublishableKey string
    // StripeWebhookSecret string
}

func Load() *Config {
    cfg := &Config{
        DatabaseURL: os.Getenv("DATABASE_URL"),
        Port:        getEnvOrDefault("PORT", "3000"),
        Env:         getEnvOrDefault("ENV", "development"),
        Site: SiteConfig{
            Name:           getEnvOrDefault("SITE_NAME", "$ARGUMENTS"),
            URL:            getEnvOrDefault("SITE_URL", "http://localhost:3000"),
            DefaultOGImage: getEnvOrDefault("DEFAULT_OG_IMAGE", "/static/images/og-default.png"),
        },
    }

    if cfg.DatabaseURL == "" {
        slog.Error("DATABASE_URL environment variable is required")
        os.Exit(1)
    }

    return cfg
}

func (c *Config) IsDevelopment() bool {
    return c.Env == "development"
}

func (c *Config) IsProduction() bool {
    return c.Env == "production"
}

func getEnvOrDefault(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}
```

#### 13. internal/ctxkeys/keys.go

Typed context keys to prevent collision with other packages:

```go
package ctxkeys

type siteConfigKey struct{}

var SiteConfig = siteConfigKey{}
```

#### 14. internal/meta/meta.go

SEO and Open Graph metadata (simple struct, no site name - that comes from context):

```go
package meta

type PageMeta struct {
    Title       string
    Description string
    OGType      string
    OGImage     string
    Canonical   string
    NoIndex     bool
}

func New(title, description string) PageMeta {
    return PageMeta{
        Title:       title,
        Description: description,
        OGType:      "website",
    }
}

func (m PageMeta) WithOGImage(url string) PageMeta {
    m.OGImage = url
    return m
}

func (m PageMeta) WithCanonical(url string) PageMeta {
    m.Canonical = url
    return m
}

func (m PageMeta) AsArticle() PageMeta {
    m.OGType = "article"
    return m
}

func (m PageMeta) AsProduct() PageMeta {
    m.OGType = "product"
    return m
}
```

#### 15. internal/meta/context.go

Context helpers to access site config from templates:

```go
package meta

import (
    "context"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/ctxkeys"
)

func SiteFromCtx(ctx context.Context) config.SiteConfig {
    if cfg, ok := ctx.Value(ctxkeys.SiteConfig).(config.SiteConfig); ok {
        return cfg
    }
    return config.SiteConfig{Name: "$ARGUMENTS"}
}

func SiteNameFromCtx(ctx context.Context) string {
    return SiteFromCtx(ctx).Name
}

func SiteURLFromCtx(ctx context.Context) string {
    return SiteFromCtx(ctx).URL
}
```

#### 16. internal/database/database.go

**For PostgreSQL:**

```go
package database

import (
    "context"
    "fmt"

    "github.com/jackc/pgx/v5/pgxpool"
    "$ARGUMENTS/internal/database/sqlc"
)

type DB struct {
    Pool    *pgxpool.Pool
    Queries *sqlc.Queries
}

func New(ctx context.Context, databaseURL string) (*DB, error) {
    pool, err := pgxpool.New(ctx, databaseURL)
    if err != nil {
        return nil, fmt.Errorf("unable to create connection pool: %w", err)
    }

    if err := pool.Ping(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    return &DB{
        Pool:    pool,
        Queries: sqlc.New(pool),
    }, nil
}

func (db *DB) Close() {
    db.Pool.Close()
}
```

**For SQLite (CGO-free):**

```go
package database

import (
    "context"
    "database/sql"
    "fmt"

    _ "modernc.org/sqlite"
    "$ARGUMENTS/internal/database/sqlc"
)

type DB struct {
    Conn    *sql.DB
    Queries *sqlc.Queries
}

func New(ctx context.Context, databasePath string) (*DB, error) {
    conn, err := sql.Open("sqlite", databasePath+"?_foreign_keys=on")
    if err != nil {
        return nil, fmt.Errorf("unable to open database: %w", err)
    }

    if err := conn.PingContext(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    return &DB{
        Conn:    conn,
        Queries: sqlc.New(conn),
    }, nil
}

func (db *DB) Close() {
    db.Conn.Close()
}
```

**For MySQL:**

```go
package database

import (
    "context"
    "database/sql"
    "fmt"

    _ "github.com/go-sql-driver/mysql"
    "$ARGUMENTS/internal/database/sqlc"
)

type DB struct {
    Conn    *sql.DB
    Queries *sqlc.Queries
}

func New(ctx context.Context, dsn string) (*DB, error) {
    conn, err := sql.Open("mysql", dsn)
    if err != nil {
        return nil, fmt.Errorf("unable to open database: %w", err)
    }

    if err := conn.PingContext(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    return &DB{
        Conn:    conn,
        Queries: sqlc.New(conn),
    }, nil
}

func (db *DB) Close() {
    db.Conn.Close()
}
```

#### 17. internal/middleware/middleware.go

```go
package middleware

import (
    "context"
    "log/slog"
    "time"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/ctxkeys"

    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
)

func Setup(e *echo.Echo, cfg *config.Config) {
    e.Use(middleware.RequestID())
    e.Use(middleware.Recover())
    e.Use(SiteConfigMiddleware(cfg.Site))
    e.Use(requestLogger(cfg.IsDevelopment()))
    e.Use(middleware.CORSWithConfig(middleware.CORSConfig{
        AllowOrigins: []string{"*"},
        AllowMethods: []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
    }))
    e.Use(middleware.GzipWithConfig(middleware.GzipConfig{
        Level: 5,
    }))
    e.Use(middleware.SecureWithConfig(middleware.SecureConfig{
        XSSProtection:         "1; mode=block",
        ContentTypeNosniff:    "nosniff",
        XFrameOptions:         "SAMEORIGIN",
        HSTSMaxAge:            31536000,
        ContentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com; style-src 'self' 'unsafe-inline';",
    }))
}

func SiteConfigMiddleware(site config.SiteConfig) echo.MiddlewareFunc {
    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            ctx := context.WithValue(c.Request().Context(), ctxkeys.SiteConfig, site)
            c.SetRequest(c.Request().WithContext(ctx))
            return next(c)
        }
    }
}

func requestLogger(isDev bool) echo.MiddlewareFunc {
    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            start := time.Now()
            err := next(c)
            latency := time.Since(start)

            req := c.Request()
            res := c.Response()

            attrs := []any{
                "request_id", c.Response().Header().Get(echo.HeaderXRequestID),
                "method", req.Method,
                "uri", req.RequestURI,
                "status", res.Status,
                "latency", latency.String(),
            }

            if isDev {
                slog.Debug("request", attrs...)
            } else if res.Status >= 500 {
                slog.Error("request", attrs...)
            } else {
                slog.Info("request", attrs...)
            }

            return err
        }
    }
}
```

#### 18. internal/handler/handler.go

```go
package handler

import (
    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/database"

    "github.com/labstack/echo/v4"
)

type Handler struct {
    cfg *config.Config
    db  *database.DB
}

func New(cfg *config.Config, db *database.DB) *Handler {
    return &Handler{
        cfg: cfg,
        db:  db,
    }
}

func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // Static files
    e.Static("/static", "static")

    // Health check
    e.GET("/health", h.Health)

    // Public routes
    e.GET("/", h.Home)

    // Admin routes (if dashboard selected)
    // admin := e.Group("/admin")
    // admin.GET("", h.AdminDashboard)
}
```

#### 19. internal/handler/home.go

Handlers do NOT construct meta - that's the template's job:

```go
package handler

import (
    "net/http"

    "$ARGUMENTS/templates/pages"

    "github.com/labstack/echo/v4"
)

func (h *Handler) Health(c echo.Context) error {
    return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) Home(c echo.Context) error {
    return pages.Home().Render(c.Request().Context(), c.Response().Writer)
}
```

### Template Files

#### 20. templates/layouts/meta.templ

Meta tags component - site name comes from context, not the struct:

```templ
package layouts

import "$ARGUMENTS/internal/meta"

templ MetaTags(m meta.PageMeta) {
    <title>{ m.Title } | { meta.SiteNameFromCtx(ctx) }</title>
    if m.Description != "" {
        <meta name="description" content={ m.Description }/>
    }
    if m.Canonical != "" {
        <link rel="canonical" href={ m.Canonical }/>
    }
    if m.NoIndex {
        <meta name="robots" content="noindex, nofollow"/>
    }

    // Open Graph - site name always from context
    <meta property="og:title" content={ m.Title }/>
    <meta property="og:site_name" content={ meta.SiteNameFromCtx(ctx) }/>
    <meta property="og:type" content={ m.OGType }/>
    if m.Description != "" {
        <meta property="og:description" content={ m.Description }/>
    }
    if m.OGImage != "" {
        <meta property="og:image" content={ m.OGImage }/>
    }

    // Twitter Card
    <meta name="twitter:card" content="summary_large_image"/>
    <meta name="twitter:title" content={ m.Title }/>
    if m.Description != "" {
        <meta name="twitter:description" content={ m.Description }/>
    }
    if m.OGImage != "" {
        <meta name="twitter:image" content={ m.OGImage }/>
    }
}
```

#### 21. templates/layouts/base.templ

Base layout receives meta from the page template, not the handler:

```templ
package layouts

import "$ARGUMENTS/internal/meta"

templ Base(m meta.PageMeta) {
    <!DOCTYPE html>
    <html lang="en">
        <head>
            <meta charset="UTF-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            @MetaTags(m)
            <link rel="stylesheet" href="/static/css/output.css"/>
            <script src="https://unpkg.com/htmx.org@2.0.4"></script>
            <script defer src="https://unpkg.com/alpinejs@3.14.8/dist/cdn.min.js"></script>
        </head>
        <body class="bg-background text-foreground min-h-screen">
            <header class="border-b border-border">
                <nav class="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
                    <a href="/" class="text-xl font-bold">{ meta.SiteNameFromCtx(ctx) }</a>
                    <div class="flex gap-4">
                        <a href="/" class="hover:text-primary">Home</a>
                    </div>
                </nav>
            </header>
            <main class="max-w-7xl mx-auto px-4 py-8">
                { children... }
            </main>
            <footer class="border-t border-border mt-auto">
                <div class="max-w-7xl mx-auto px-4 py-4 text-center text-muted-foreground">
                    <p>&copy; 2025 { meta.SiteNameFromCtx(ctx) }. All rights reserved.</p>
                </div>
            </footer>
        </body>
    </html>
}
```

#### 22. templates/pages/home.templ

Template constructs its own meta - handler doesn't pass it:

```templ
package pages

import (
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/templates/layouts"
)

templ Home() {
    @layouts.Base(meta.New("Home", "Your Go web application is ready!")) {
        <div class="text-center py-12">
            <h1 class="text-4xl font-bold mb-4">Welcome</h1>
            <p class="text-muted-foreground mb-8">Your Go web application is ready!</p>
            <div class="flex justify-center gap-4">
                <a href="/health" class="px-6 py-3 bg-primary text-primary-foreground rounded-lg hover:bg-primary/90">
                    Check Health
                </a>
            </div>
        </div>

        <div class="mt-12 grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            <div class="p-6 border border-border rounded-lg">
                <h3 class="font-semibold mb-2">Fast Development</h3>
                <p class="text-muted-foreground text-sm">Hot reload with Air. Changes appear instantly.</p>
            </div>
            <div class="p-6 border border-border rounded-lg">
                <h3 class="font-semibold mb-2">Type-Safe Templates</h3>
                <p class="text-muted-foreground text-sm">Templ compiles to Go for compile-time safety.</p>
            </div>
            <div class="p-6 border border-border rounded-lg">
                <h3 class="font-semibold mb-2">Modern Styling</h3>
                <p class="text-muted-foreground text-sm">Tailwind CSS v4 with dark mode support.</p>
            </div>
            <div class="p-6 border border-border rounded-lg">
                <h3 class="font-semibold mb-2">Client Interactivity</h3>
                <p class="text-muted-foreground text-sm">Alpine.js for dropdowns, modals, and tabs.</p>
            </div>
        </div>
    }
}
```

### Static Files

#### 23. static/css/input.css

```css
@import "tailwindcss";

@source "../../templates/**/*.templ";

@theme {
  /* Light mode (default) */
  --color-background: oklch(1 0 0);
  --color-foreground: oklch(0.145 0 0);
  --color-card: oklch(1 0 0);
  --color-border: oklch(0.9 0 0);
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
  --color-muted: oklch(0.95 0 0);
  --color-muted-foreground: oklch(0.4 0 0);
}

@variant dark {
  --color-background: oklch(0.145 0 0);
  --color-foreground: oklch(0.985 0 0);
  --color-card: oklch(0.205 0 0);
  --color-border: oklch(0.3 0 0);
  --color-primary: oklch(0.6 0.2 250);
  --color-primary-foreground: oklch(1 0 0);
  --color-muted: oklch(0.25 0 0);
  --color-muted-foreground: oklch(0.6 0 0);
}

@layer base {
  html {
    font-family: ui-sans-serif, system-ui, sans-serif;
  }
}
```

#### 24. static/js/.gitkeep

Create empty file to preserve directory.

### Admin Dashboard Files (if selected)

If the user selected Yes for admin dashboard, also create:

#### 25. templates/layouts/admin.templ

Include the admin layout with:

- FOUC prevention script for dark mode
- Sidebar navigation
- Theme toggle
- Mobile responsive design

#### 26. templates/components/theme/theme.templ

Dark/light mode toggle component with:

- Moon/sun icons
- localStorage persistence
- html.classList toggle

#### 27. templates/components/sidebar/sidebar.templ

Collapsible sidebar with:

- Navigation sections
- Active state detection
- Mobile sheet integration

#### 28. templates/pages/admin/dashboard.templ

Dashboard page with:

- Stats cards
- Quick actions
- Recent activity

#### 29. internal/handler/admin.go

Admin route handlers.

### Deployment Files

Based on the deployment platform selected:

**For Vercel:** Create `vercel.json`, `api/index.go`, and `public/` directory.

**For Railway:** Create `railway.toml`.

**For Fly.io:** Create `fly.toml` and `Dockerfile`.

**For Self-hosted:** Create `Dockerfile` only.

### Project Documentation

#### 30. CLAUDE.md

Create a CLAUDE.md file with the following content (adjust project name):

The CLAUDE.md should contain:

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

---

## Step 3: Initialize and Finalize

After creating all files:

1. **Initialize git:**

   ```bash
   cd $ARGUMENTS
   git init
   ```

2. **Install dependencies:**

   ```bash
   go mod tidy
   npm install
   ```

3. **Generate code:**

   ```bash
   make generate
   ```

4. **Create initial commit:**

   ```bash
   git add .
   git commit -m "Initial project setup with Go + Templ + HTMX + Tailwind"
   ```

---

## Step 4: Display Summary

After project creation, display a summary to the user showing:

**Project Created Header:**

- Project name: $ARGUMENTS
- Location: ./$ARGUMENTS

**Files Created Table:**

| Directory | Count | Purpose |
|-----------|-------|---------|
| cmd/server/ | 2 | Entry point |
| internal/ | 5+ | Core Go code |
| templates/ | 3+ | Templ templates |
| migrations/ | 1 | Database schema |
| sqlc/ | 2 | Query definitions |
| static/ | 2 | CSS/JS assets |
| Root | 8 | Config files |

**Next Steps Instructions:**

1. Configure environment: `cp .envrc.example .envrc`, edit with database URL, run `direnv allow`
1. Install tools (first time only): `make setup` and `npm install`
1. Set up database: Create database, then run `make migrate`
1. Start developing: `make dev`
1. Open browser: `http://localhost:3000`

**Key Commands Table:**

| Command | What it does |
|---------|--------------|
| `make dev` | Start with hot reload (main workflow) |
| `make build` | Build production binary |
| `make test` | Run all tests |
| `make generate` | Regenerate templ + sqlc code |
| `make migrate` | Apply database migrations |
| `make css-watch` | Watch and rebuild CSS |

**Deployment Section:**

Display deployment instructions based on the platform the user selected earlier.
