---
argument-hint: "<project-name>"
description: "Create a new Go web project with Templ, HTMX, Tailwind, and sqlc"
model: claude-opus-4-6
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
- **templUI** (optional) - Component library for Templ (if admin dashboard selected)
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
- **templUI component library** (requires installation - see below)

**If Admin Dashboard is selected:**

The admin dashboard uses [templUI](https://templui.io), a component library for Templ. After project creation, install the templUI CLI and add the required components:

```bash
# Install templUI CLI
go install github.com/templui/templui@latest

# Add required components for admin dashboard
templui add sidebar button card icon
```

This will create a `components/` directory with the templUI components. The generated `input.css` already includes the source path for this directory.

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
  Good choice for SQLite or if you want a traditional server setup. Uses Nixpacks by default.

- **Fly.io**: Runs your app in multiple locations worldwide for faster access.
  More setup required (Docker helps) but great for global users. Works well with
  SQLite (persistent volumes) or any database.

- **Self-hosted**: You manage the server yourself. More work but full control.
  Best for SQLite production deployments.

**Example recommendation flow:**

- User: "Where should I deploy?" → Default to Vercel + Neon
- User chose SQLite earlier → Recommend Railway or Fly.io
- User: "I need to self-host" → Provide self-hosted guidance

### Build Method (for Railway, Fly.io, and Self-hosted)

After selecting a deployment platform that runs the app as a server (Railway, Fly.io, or Self-hosted), ask the user how they want to build:

| Build Method | When to Use |
|--------------|-------------|
| **Nixpacks** (recommended) | Simplest option — auto-detects Go, builds and runs with zero config. Used by Railway, Coolify, Dokploy, and other modern PaaS platforms. |
| **Dockerfile** | Full control over build environment. Required for Fly.io. Use when you need custom system packages, multi-stage builds, or specific base images. |
| **Plain binary** | No containerization — just `make build` and run the binary directly. Good for VPS/bare-metal deployments with systemd. |

**Plain explanations for beginners:**

- **Nixpacks**: Like a smart auto-builder. It looks at your code, figures out it's
  Go, and builds it automatically. No configuration file needed for basic apps, but
  you can add a `nixpacks.toml` for customization. Railway uses this by default.

- **Dockerfile**: A recipe file that tells Docker exactly how to build your app.
  More verbose but gives you complete control. Required for Fly.io deployments.

- **Plain binary**: Skip containers entirely. Run `make build` to get a binary,
  copy it to your server, run it. Simplest for a single VPS with systemd.

---

## Loop Initialization

Initialize persistent loop to ensure project creation completes fully:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "create-go-project-$ARGUMENTS" "COMPLETE"`

## Security Validation

Before creating any files, validate the project name:

1. **Check for path traversal**: If `$ARGUMENTS` contains `/`, `..`, or starts with `.`, display error: "Project name cannot contain path separators or relative paths"
2. **Check for valid characters**: If `$ARGUMENTS` contains characters other than `a-z`, `A-Z`, `0-9`, `-`, or `_`, display error: "Project name must contain only alphanumeric characters, hyphens, and underscores"
3. **Check for reserved names**: If `$ARGUMENTS` is empty or matches system directories, display error

Only proceed if validation passes.

## Step 2: Create Project Structure

After gathering requirements, create the project at `./$ARGUMENTS/`.

### Core Files

Create these files in order (dependencies matter):

#### 1. go.mod

```go
module $ARGUMENTS

go 1.25

require (
    github.com/go-chi/chi/v5 v5.2.1
    github.com/labstack/echo/v4 v4.14.0
    github.com/a-h/templ v0.3.960
    github.com/lmittmann/tint v1.1.2
    github.com/pressly/goose/v3 v3.26.0
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

# SQLite database files
data/*.db

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

#### 4. .envrc (working environment file)

**IMPORTANT:** Also create the actual `.envrc` file with working defaults based on the selected database:

**For SQLite:**
```bash
# Environment configuration for $ARGUMENTS
# Automatically generated - modify as needed

# Database (SQLite)
export DATABASE_URL="./data/$ARGUMENTS.db"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="$ARGUMENTS"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

**For PostgreSQL:**
```bash
# Environment configuration for $ARGUMENTS
# Automatically generated - modify DATABASE_URL with your credentials

# Database (PostgreSQL) - UPDATE WITH YOUR CREDENTIALS
export DATABASE_URL="postgres://localhost:5432/$ARGUMENTS?sslmode=disable"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="$ARGUMENTS"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

**For MySQL:**
```bash
# Environment configuration for $ARGUMENTS
# Automatically generated - modify DATABASE_URL with your credentials

# Database (MySQL) - UPDATE WITH YOUR CREDENTIALS
export DATABASE_URL="root@tcp(localhost:3306)/$ARGUMENTS"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="$ARGUMENTS"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

#### 5. data/.gitkeep (for SQLite projects only)

For SQLite projects, create the data directory:

```bash
mkdir -p data
touch data/.gitkeep
```

This ensures the database directory exists and is tracked by git (but not the database file itself, which is in .gitignore).

#### 6. package.json

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

.PHONY: dev build test lint generate sqlc-vet css css-watch migrate migrate-down migrate-status migrate-create setup clean run help

BINARY_NAME=$ARGUMENTS
MIGRATIONS_DIR=internal/database/migrations

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
    go generate ./...

sqlc-vet:
	@if [ -z "$$DATABASE_URL" ]; then \
		echo "Error: DATABASE_URL not set"; \
		echo "For local development: source .envrc"; \
		echo "For CI: set DATABASE_URL environment variable"; \
		exit 1; \
	fi
	@echo "Validating SQL queries against database schema..."
	sqlc vet -f sqlc/sqlc.yaml

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
    @echo "  sqlc-vet       - Validate SQL queries against database (requires DATABASE_URL)"
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
    "go generate ./...",
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
    schema: "../internal/database/migrations/"
    database:
      uri: ${DATABASE_URL}
      managed: false
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
    schema: "../internal/database/migrations/"
    database:
      uri: ${DATABASE_URL}
      managed: false
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
    schema: "../internal/database/migrations/"
    database:
      uri: ${DATABASE_URL}
      managed: false
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

#### 9. internal/database/migrations/001_initial.sql

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

#### 11. cmd/server/generate.go

This file centralizes all code generation via `//go:generate` directives:

```go
package main

//go:generate echo "Generating SQLC files..."
//go:generate sqlc generate -f ../../sqlc/sqlc.yaml
//go:generate echo "SQLC files generated"

//go:generate echo "Generating templ files..."
//go:generate templ generate -path ../../templates
//go:generate echo "templ files generated"

//go:generate echo "Generating Tailwind CSS..."
//go:generate npx @tailwindcss/cli -i ../../static/css/input.css -o ../../static/css/output.css
//go:generate echo "Tailwind CSS generated"
```

#### 12. cmd/server/main.go

```go
package main

import (
    "context"
    "errors"
    "fmt"
    "log/slog"
    "net"
    "os"
    "os/signal"
    "strconv"
    "strings"
    "syscall"
    "time"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/database"
    "$ARGUMENTS/internal/handler"
    "$ARGUMENTS/internal/middleware"

    chimw "github.com/go-chi/chi/v5/middleware"
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

    ln, actualPort, err := findAvailablePort(cfg.Port)
    if err != nil {
        slog.Error("failed to find available port", "error", err)
        os.Exit(1)
    }
    e.Listener = ln

    if actualPort != cfg.Port {
        slog.Warn("configured port unavailable, using next available", "configured", cfg.Port, "actual", actualPort)
        cfg.Port = actualPort
        cfg.Site.URL = replacePort(cfg.Site.URL, actualPort)
    }

    middleware.Setup(e, cfg)

    h := handler.New(cfg, db)
    h.RegisterRoutes(e)

    e.Use(echo.WrapMiddleware(chimw.Logger))

    go func() {
        slog.Info("starting server", "url", fmt.Sprintf("http://localhost:%s", cfg.Port), "env", cfg.Env)
        if err := e.Start(""); err != nil {
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

func findAvailablePort(configuredPort string) (net.Listener, string, error) {
    startPort, err := strconv.Atoi(configuredPort)
    if err != nil {
        return nil, "", fmt.Errorf("invalid port %q: %w", configuredPort, err)
    }

    maxPort := startPort + 100
    for port := startPort; port <= maxPort; port++ {
        addr := ":" + strconv.Itoa(port)
        ln, err := net.Listen("tcp", addr)
        if err != nil {
            // Only retry for "address in use" errors; return other errors immediately
            if !errors.Is(err, syscall.EADDRINUSE) {
                return nil, "", fmt.Errorf("failed to listen on port %d: %w", port, err)
            }
            continue
        }
        // Get actual bound port (important when port is 0)
        actualPort := ln.Addr().(*net.TCPAddr).Port
        return ln, strconv.Itoa(actualPort), nil
    }

    return nil, "", fmt.Errorf("no available port found in range %d-%d", startPort, maxPort)
}

func replacePort(rawURL string, newPort string) string {
    const localhostPrefix = "://localhost:"
    if idx := strings.Index(rawURL, localhostPrefix); idx >= 0 {
        afterScheme := idx + len(localhostPrefix)
        end := strings.IndexAny(rawURL[afterScheme:], "/?#")
        if end == -1 {
            return rawURL[:afterScheme] + newPort
        }
        return rawURL[:afterScheme] + newPort + rawURL[afterScheme+end:]
    }
    return rawURL
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

#### 17. internal/database/database.go

**For PostgreSQL:**

```go
package database

import (
    "context"
    "embed"
    "fmt"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/jackc/pgx/v5/stdlib"
    "github.com/pressly/goose/v3"
    "$ARGUMENTS/internal/database/sqlc"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

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

    db := &DB{
        Pool:    pool,
        Queries: sqlc.New(pool),
    }

    if err := db.migrate(); err != nil {
        return nil, fmt.Errorf("unable to run migrations: %w", err)
    }

    return db, nil
}

func (db *DB) Close() {
    db.Pool.Close()
}

func (db *DB) migrate() error {
    goose.SetBaseFS(migrationsFS)

    if err := goose.SetDialect("postgres"); err != nil {
        return fmt.Errorf("failed to set goose dialect: %w", err)
    }

    // Get stdlib connection for goose
    conn := stdlib.OpenDBFromPool(db.Pool)
    defer conn.Close()

    if err := goose.Up(conn, "migrations"); err != nil {
        return fmt.Errorf("failed to run migrations: %w", err)
    }

    return nil
}
```

**For SQLite (CGO-free):**

```go
package database

import (
    "context"
    "database/sql"
    "embed"
    "fmt"
    "os"
    "path/filepath"

    "github.com/pressly/goose/v3"
    _ "modernc.org/sqlite"
    "$ARGUMENTS/internal/database/sqlc"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

type DB struct {
    Conn    *sql.DB
    Queries *sqlc.Queries
}

func New(ctx context.Context, databasePath string) (*DB, error) {
    dir := filepath.Dir(databasePath)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return nil, fmt.Errorf("unable to create database directory: %w", err)
    }

    conn, err := sql.Open("sqlite", databasePath+"?_foreign_keys=on&_journal_mode=WAL")
    if err != nil {
        return nil, fmt.Errorf("unable to open database: %w", err)
    }

    if err := conn.PingContext(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    db := &DB{
        Conn:    conn,
        Queries: sqlc.New(conn),
    }

    if err := db.migrate(); err != nil {
        return nil, fmt.Errorf("unable to run migrations: %w", err)
    }

    return db, nil
}

func (db *DB) Close() {
    db.Conn.Close()
}

func (db *DB) migrate() error {
    goose.SetBaseFS(migrationsFS)

    if err := goose.SetDialect("sqlite3"); err != nil {
        return fmt.Errorf("failed to set goose dialect: %w", err)
    }

    if err := goose.Up(db.Conn, "migrations"); err != nil {
        return fmt.Errorf("failed to run migrations: %w", err)
    }

    return nil
}
```

**For MySQL:**

```go
package database

import (
    "context"
    "database/sql"
    "embed"
    "fmt"

    "github.com/pressly/goose/v3"
    _ "github.com/go-sql-driver/mysql"
    "$ARGUMENTS/internal/database/sqlc"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

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

    db := &DB{
        Conn:    conn,
        Queries: sqlc.New(conn),
    }

    if err := db.migrate(); err != nil {
        return nil, fmt.Errorf("unable to run migrations: %w", err)
    }

    return db, nil
}

func (db *DB) Close() {
    db.Conn.Close()
}

func (db *DB) migrate() error {
    goose.SetBaseFS(migrationsFS)

    if err := goose.SetDialect("mysql"); err != nil {
        return fmt.Errorf("failed to set goose dialect: %w", err)
    }

    if err := goose.Up(db.Conn, "migrations"); err != nil {
        return fmt.Errorf("failed to run migrations: %w", err)
    }

    return nil
}
```

#### 18. internal/middleware/middleware.go

```go
package middleware

import (
    "context"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/ctxkeys"

    "github.com/labstack/echo/v4"
    "github.com/labstack/echo/v4/middleware"
)

func Setup(e *echo.Echo, cfg *config.Config) {
    e.Use(middleware.RequestID())
    e.Use(middleware.Recover())
    e.Use(SiteConfigMiddleware(cfg.Site))
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
    // If using templUI (admin dashboard), uncomment:
    // e.Static("/assets", "assets")

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

Base layout receives meta from the page template, not the handler.

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

**If Admin Dashboard was selected (using templUI):**

When using templUI components, you MUST include their Script() templates in the `<head>`. Update base.templ to add the imports and Script() calls:

```templ
package layouts

import (
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/components/sidebar"
    "$ARGUMENTS/components/dialog"
)

templ Base(m meta.PageMeta) {
    <!DOCTYPE html>
    <html lang="en">
        <head>
            <meta charset="UTF-8"/>
            <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
            @MetaTags(m)
            <link rel="stylesheet" href="/static/css/output.css"/>
            <script src="https://unpkg.com/htmx.org@2.0.4"></script>
            @sidebar.Script()
            @dialog.Script()
        </head>
        // ... rest of body
    </html>
}
```

| Component | Requires Script() from |
|-----------|------------------------|
| sidebar | `sidebar.Script()` |
| dropdown | `popover.Script()` |
| tooltip | `popover.Script()` |
| combobox | `popover.Script()` |
| sheet | `dialog.Script()` |
| alertdialog | `dialog.Script()` |
| collapsible | `accordion.Script()` |
| tabs | `tabs.Script()` |

**Note:** templUI does NOT use Alpine.js. It uses vanilla JavaScript delivered via Script() templates.

> **CRITICAL: Templ Interpolation in JavaScript**
> Go expressions `{ value }` do NOT work inside `<script>` tags or inline event handler strings.
> - **Data attributes**: `data-id={ value }` + `this.dataset.id` in JS
> - **templ.JSFuncCall**: `onclick={ templ.JSFuncCall("fn", value) }` for onclick handlers
> - **Double braces**: `{{ value }}` (double braces) inside `<script>` tag strings
>
> If you see `%7B` or `%7D` in URLs, that's a literal `{` or `}` that wasn't interpolated.

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
                <p class="text-muted-foreground text-sm">HTMX for server-driven interactivity.</p>
            </div>
        </div>
    }
}
```

### Static Files

#### 23. static/css/input.css

Use the appropriate version based on whether Admin Dashboard was selected:

**Basic version (No Admin Dashboard):**

```css
@import "tailwindcss";

@source "../../templates/**/*.templ";

@custom-variant dark (&:where(.dark, .dark *));

/* Light mode (default) */
:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
}

/* Dark mode */
.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --primary-foreground: oklch(0.205 0 0);
  --secondary: oklch(0.269 0 0);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
}

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-destructive: var(--destructive);
  --color-border: var(--border);
}

@layer base {
  * {
    @apply border-border;
  }
  html {
    @apply scroll-smooth;
  }
  body {
    @apply bg-background text-foreground;
  }
}
```

**templUI version (With Admin Dashboard):**

This version includes additional source paths and CSS variables required for templUI components.
After creating this file, install templUI: `go install github.com/templui/templui@latest && templui add sidebar button card icon`

```css
@import "tailwindcss";

@source "../../templates/**/*.templ";
@source "../../components/**/*.templ";

@custom-variant dark (&:where(.dark, .dark *));

@theme inline {
  --font-sans: ui-sans-serif, system-ui, sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji";
  --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Consolas, "Liberation Mono", Menlo, monospace;
  --radius-sm: calc(var(--radius) - 4px);
  --radius-md: calc(var(--radius) - 2px);
  --radius-lg: var(--radius);
  --radius-xl: calc(var(--radius) + 4px);
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-card: var(--card);
  --color-card-foreground: var(--card-foreground);
  --color-popover: var(--popover);
  --color-popover-foreground: var(--popover-foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-secondary: var(--secondary);
  --color-secondary-foreground: var(--secondary-foreground);
  --color-muted: var(--muted);
  --color-muted-foreground: var(--muted-foreground);
  --color-accent: var(--accent);
  --color-accent-foreground: var(--accent-foreground);
  --color-destructive: var(--destructive);
  --color-border: var(--border);
  --color-input: var(--input);
  --color-ring: var(--ring);
  --color-sidebar: var(--sidebar);
  --color-sidebar-foreground: var(--sidebar-foreground);
  --color-sidebar-primary: var(--sidebar-primary);
  --color-sidebar-primary-foreground: var(--sidebar-primary-foreground);
  --color-sidebar-accent: var(--sidebar-accent);
  --color-sidebar-accent-foreground: var(--sidebar-accent-foreground);
  --color-sidebar-border: var(--sidebar-border);
  --color-sidebar-ring: var(--sidebar-ring);
}

/* Light mode (default) */
:root {
  --radius: 0.625rem;
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
  --sidebar: oklch(0.985 0 0);
  --sidebar-foreground: oklch(0.145 0 0);
  --sidebar-primary: oklch(0.205 0 0);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.97 0 0);
  --sidebar-accent-foreground: oklch(0.205 0 0);
  --sidebar-border: oklch(0.922 0 0);
  --sidebar-ring: oklch(0.708 0 0);
}

/* Dark mode */
.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --card: oklch(0.205 0 0);
  --card-foreground: oklch(0.985 0 0);
  --popover: oklch(0.205 0 0);
  --popover-foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --primary-foreground: oklch(0.205 0 0);
  --secondary: oklch(0.269 0 0);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
  --sidebar: oklch(0.205 0 0);
  --sidebar-foreground: oklch(0.985 0 0);
  --sidebar-primary: oklch(0.488 0.243 264.376);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.269 0 0);
  --sidebar-accent-foreground: oklch(0.985 0 0);
  --sidebar-border: oklch(1 0 0 / 10%);
  --sidebar-ring: oklch(0.556 0 0);
}

@layer base {
  * {
    @apply border-border;
  }
  html {
    @apply scroll-smooth;
  }
  body {
    @apply bg-background text-foreground;
  }
}
```

**Key points:**
- `@source "../../components/**/*.templ"` - Required for templUI components
- `@custom-variant dark` - Tailwind CSS v4 dark mode syntax (NOT `@variant dark`)
- Complete CSS variable definitions for templUI compatibility
- Sidebar-specific variables for templUI sidebar component

#### 24. static/js/.gitkeep

Create empty file to preserve directory.

### CI/CD and Quality Files

#### 25. .github/workflows/ci.yml

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: '1.25'
      - name: golangci-lint
        uses: golangci/golangci-lint-action@v9
        with:
          version: v2.6

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: '1.25'
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install Go tools
        run: |
          go install github.com/a-h/templ/cmd/templ@latest
          go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
      - name: Install npm dependencies
        run: npm ci
      - name: Generate code
        run: go generate ./...
      - name: Run tests
        run: go test -v -race ./...

  build:
    runs-on: ubuntu-latest
    needs: [lint, test]
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: '1.25'
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Install Go tools
        run: |
          go install github.com/a-h/templ/cmd/templ@latest
          go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
      - name: Install npm dependencies
        run: npm ci
      - name: Generate code
        run: go generate ./...
      - name: Build
        run: go build -o bin/$ARGUMENTS ./cmd/server

  # === SQLC Query Validation Job ===
  # GENERATOR: Include ONLY the job matching the selected database engine.

  # --- For PostgreSQL projects: ---
  sqlc-vet:
    name: SQLC Query Validation
    runs-on: ubuntu-latest
    timeout-minutes: 10
    services:
      postgres:
        image: pgvector/pgvector:pg17
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: testdb
        options: >-
          --health-cmd "pg_isready -U test"
          --health-interval 5s
          --health-timeout 3s
          --health-retries 3
          --health-start-period 5s
        ports:
          - 5432:5432
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-go@v6
        with:
          go-version: '1.25'
      - name: Install tools
        run: |
          go install github.com/pressly/goose/v3/cmd/goose@latest
          go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
      - name: Run migrations
        env:
          DATABASE_URL: "postgresql://test:test@localhost:5432/testdb?sslmode=disable"
        run: |
          goose -dir internal/database/migrations postgres "$DATABASE_URL" up
      - name: Validate SQL queries
        env:
          DATABASE_URL: "postgresql://test:test@localhost:5432/testdb?sslmode=disable"
        run: |
          sqlc vet -f sqlc/sqlc.yaml

  # --- For SQLite projects: ---
  # sqlc-vet:
  #   name: SQLC Query Validation
  #   runs-on: ubuntu-latest
  #   timeout-minutes: 5
  #   steps:
  #     - uses: actions/checkout@v5
  #     - uses: actions/setup-go@v6
  #       with:
  #         go-version: '1.25'
  #     - name: Install tools
  #       run: |
  #         go install github.com/pressly/goose/v3/cmd/goose@latest
  #         go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
  #     - name: Setup database and run migrations
  #       env:
  #         DATABASE_URL: "./data/test.db"
  #       run: |
  #         mkdir -p data
  #         goose -dir internal/database/migrations sqlite3 "$DATABASE_URL" up
  #     - name: Validate SQL queries
  #       env:
  #         DATABASE_URL: "./data/test.db"
  #       run: |
  #         sqlc vet -f sqlc/sqlc.yaml

  # --- For MySQL projects: ---
  # sqlc-vet:
  #   name: SQLC Query Validation
  #   runs-on: ubuntu-latest
  #   timeout-minutes: 10
  #   services:
  #     mysql:
  #       image: mysql:8
  #       env:
  #         MYSQL_ROOT_PASSWORD: test
  #         MYSQL_DATABASE: testdb
  #       options: >-
  #         --health-cmd "mysqladmin ping -h localhost"
  #         --health-interval 5s
  #         --health-timeout 3s
  #         --health-retries 3
  #         --health-start-period 10s
  #       ports:
  #         - 3306:3306
  #   steps:
  #     - uses: actions/checkout@v5
  #     - uses: actions/setup-go@v6
  #       with:
  #         go-version: '1.25'
  #     - name: Install tools
  #       run: |
  #         go install github.com/pressly/goose/v3/cmd/goose@latest
  #         go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest
  #     - name: Run migrations
  #       env:
  #         DATABASE_URL: "root:test@tcp(localhost:3306)/testdb"
  #       run: |
  #         goose -dir internal/database/migrations mysql "$DATABASE_URL" up
  #     - name: Validate SQL queries
  #       env:
  #         DATABASE_URL: "root:test@tcp(localhost:3306)/testdb"
  #       run: |
  #         sqlc vet -f sqlc/sqlc.yaml
```

#### 26. .github/dependabot.yml

```yaml
version: 2
updates:
  - package-ecosystem: "gomod"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
```

#### 27. .golangci.yml

```yaml
version: "2"
run:
  timeout: 5m

linters:
  enable:
    - errcheck
    - govet
    - ineffassign
    - staticcheck
    - unused

issues:
  exclude-dirs:
    - internal/database/sqlc
```

### Test Infrastructure

#### 28. internal/testutil/testutil.go

```go
package testutil

import (
    "context"
    "testing"

    "$ARGUMENTS/internal/config"
    "$ARGUMENTS/internal/database"
)

// NewTestDB creates an in-memory SQLite database for testing.
// For PostgreSQL projects, modify to use a test database URL.
func NewTestDB(t *testing.T) *database.DB {
    t.Helper()

    ctx := context.Background()
    // For SQLite: use in-memory database
    // For PostgreSQL: use TEST_DATABASE_URL or create temp database
    db, err := database.New(ctx, ":memory:")
    if err != nil {
        t.Fatalf("failed to create test database: %v", err)
    }

    t.Cleanup(func() {
        db.Close()
    })

    return db
}

// NewTestConfig creates a test configuration.
func NewTestConfig(t *testing.T) *config.Config {
    t.Helper()

    return &config.Config{
        DatabaseURL: ":memory:",
        Port:        "0", // Use random available port
        Env:         "test",
        Site: config.SiteConfig{
            Name: "$ARGUMENTS",
            URL:  "http://localhost:3000",
        },
    }
}
```

**Note for PostgreSQL projects:** Modify `NewTestDB` to use a test database URL from environment variable `TEST_DATABASE_URL` or create a temporary test database.

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

### Clerk Integration Files (if selected)

If the user selected Clerk, create these additional files and modify existing ones.

**CRITICAL Clerk CDN Rules:**
1. The publishable key MUST be a `data-clerk-publishable-key` attribute on the `<script>` tag — NOT in a `<meta>` tag
2. Pin to major version `@clerk/clerk-js@5` — NEVER use `@latest`
3. After loading, `Clerk` is a global object — call `Clerk.load()`, NOT `new Clerk()` or `new window.Clerk()`
4. Always wrap initialization in `window.addEventListener('load', ...)` to ensure the SDK script has executed
5. In templ, use `@templ.Raw()` to render the script tag since templ doesn't support dynamic attributes on `<script>` tags

#### Update .envrc and .envrc.example

Add to both files:

```bash
# Clerk (authentication)
export CLERK_PUBLISHABLE_KEY="pk_test_YOUR_KEY_HERE"
export CLERK_SECRET_KEY="sk_test_YOUR_KEY_HERE"
```

#### Update internal/config/config.go

Uncomment and populate the Clerk fields:

```go
type Config struct {
    DatabaseURL      string
    Port             string
    Env              string
    Site             SiteConfig
    ClerkPublishableKey string
    ClerkSecretKey      string
}

func Load() *Config {
    cfg := &Config{
        // ... existing fields ...
        ClerkPublishableKey: os.Getenv("CLERK_PUBLISHABLE_KEY"),
        ClerkSecretKey:      os.Getenv("CLERK_SECRET_KEY"),
    }

    if cfg.ClerkPublishableKey == "" {
        slog.Error("CLERK_PUBLISHABLE_KEY environment variable is required")
        os.Exit(1)
    }

    // ... rest of Load() ...
}
```

#### Update internal/middleware/middleware.go

Add Clerk CSP domains and optional auth middleware:

In `Setup()`, update the ContentSecurityPolicy to allow Clerk domains:

```go
ContentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; connect-src 'self' https://*.clerk.accounts.dev; frame-src 'self' https://*.clerk.accounts.dev; img-src 'self' https://img.clerk.com;",
```

Add Clerk auth middleware for protecting routes. This requires the Clerk SDK:

**Add to go.mod:**
```go
github.com/clerk/clerk-sdk-go/v2 v2.4.1
```

**Middleware code:**

```go
import (
    "github.com/clerk/clerk-sdk-go/v2/jwt"
)

// ClerkAuth verifies Clerk session tokens and sets user info in context.
// Pass cfg.ClerkSecretKey when creating the middleware.
func ClerkAuth(clerkSecretKey string) echo.MiddlewareFunc {
    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            sessionToken := ""

            // Check cookie first (browser sessions)
            if cookie, err := c.Cookie("__session"); err == nil && cookie.Value != "" {
                sessionToken = cookie.Value
            }

            // Fall back to Authorization header (API clients)
            if sessionToken == "" {
                authHeader := c.Request().Header.Get("Authorization")
                if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
                    sessionToken = authHeader[7:]
                }
            }

            if sessionToken == "" {
                c.Set("clerk_user_id", "")
                return next(c)
            }

            // Verify the JWT with Clerk
            claims, err := jwt.Verify(c.Request().Context(), &jwt.VerifyParams{
                Token: sessionToken,
            })
            if err != nil {
                c.Set("clerk_user_id", "")
                return next(c)
            }

            c.Set("clerk_user_id", claims.Subject)
            c.Set("clerk_session_id", claims.SessionID)
            return next(c)
        }
    }
}

// RequireClerkAuth redirects to sign-in if no valid Clerk session exists.
// Must be used AFTER ClerkAuth middleware in the chain.
func RequireClerkAuth() echo.MiddlewareFunc {
    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            userID := c.Get("clerk_user_id")
            if userID == nil || userID == "" {
                return c.Redirect(302, "/sign-in")
            }
            return next(c)
        }
    }
}
```

**Usage in handler.go:**

```go
func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // Apply Clerk verification to all routes
    e.Use(middleware.ClerkAuth(h.cfg.ClerkSecretKey))

    // Public routes
    e.GET("/", h.Home)
    e.GET("/sign-in", h.SignIn)
    e.GET("/sign-up", h.SignUp)

    // Protected routes - require valid session
    protected := e.Group("", middleware.RequireClerkAuth())
    protected.GET("/dashboard", h.Dashboard)
}
```

**Note:** `ClerkAuth` verifies the JWT and sets `clerk_user_id` in context (empty string if invalid/missing). `RequireClerkAuth` checks for that value and redirects if empty. This two-middleware pattern allows some routes to optionally use auth info without requiring it.

#### templates/components/clerk/clerk.templ

Clerk script loader component using `templ.Raw()` for dynamic attributes:

```templ
package clerk

templ Script(publishableKey string) {
    @templ.Raw("<script async crossorigin=\"anonymous\" data-clerk-publishable-key=\"" + publishableKey + "\" src=\"https://cdn.jsdelivr.net/npm/@clerk/clerk-js@5/dist/clerk.browser.js\" type=\"text/javascript\"></script>")
}

templ SignIn(redirectURL string, signUpURL string) {
    <div id="sign-in" data-redirect-url={ redirectURL } data-sign-up-url={ signUpURL }></div>
    <script>
        window.addEventListener('load', async function () {
            await Clerk.load();
            const el = document.getElementById('sign-in');
            const redirectURL = el.dataset.redirectUrl;
            if (Clerk.user) {
                window.location.href = redirectURL;
                return;
            }
            Clerk.mountSignIn(el, {
                forceRedirectUrl: redirectURL,
                signUpUrl: el.dataset.signUpUrl
            });
        });
    </script>
}

templ SignUp(redirectURL string, signInURL string) {
    <div id="sign-up" data-redirect-url={ redirectURL } data-sign-in-url={ signInURL }></div>
    <script>
        window.addEventListener('load', async function () {
            await Clerk.load();
            const el = document.getElementById('sign-up');
            const redirectURL = el.dataset.redirectUrl;
            if (Clerk.user) {
                window.location.href = redirectURL;
                return;
            }
            Clerk.mountSignUp(el, {
                forceRedirectUrl: redirectURL,
                signInUrl: el.dataset.signInUrl
            });
        });
    </script>
}

templ UserButton() {
    <div id="user-button"></div>
    <script>
        window.addEventListener('load', async function () {
            await Clerk.load();
            if (Clerk.user) {
                Clerk.mountUserButton(document.getElementById('user-button'));
            }
        });
    </script>
}

templ AuthRedirect(redirectURL string) {
    <div id="auth-redirect" data-redirect-url={ redirectURL }></div>
    <script>
        window.addEventListener('load', async function () {
            await Clerk.load();
            if (Clerk.user) {
                const el = document.getElementById('auth-redirect');
                window.location.href = el.dataset.redirectUrl;
            }
        });
    </script>
}
```

#### Update templates/layouts/base.templ

Add the Clerk script to the `<head>` (it must load before any component scripts):

```templ
import "$ARGUMENTS/templates/components/clerk"

templ Base(m meta.PageMeta, clerkPublishableKey string) {
    <!DOCTYPE html>
    <html lang="en">
        <head>
            // ... existing meta, CSS, HTMX ...
            @clerk.Script(clerkPublishableKey)
        </head>
        // ... rest of body ...
    </html>
}
```

**Note:** The handler must pass `cfg.ClerkPublishableKey` when rendering any layout that includes Clerk.

**IMPORTANT - Update all existing templates:** When adding Clerk, the Base signature changes from `Base(m meta.PageMeta)` to `Base(m meta.PageMeta, clerkPublishableKey string)`. You MUST update ALL existing templates that call `@layouts.Base(m)` to use the new two-argument signature:
- For pages that need auth (sign-in, sign-up, dashboard): pass the publishable key
- For pages that don't need auth (home, notes, etc.): pass empty string `""`

Example: `@layouts.Base(meta.New("Notes", "..."))` becomes `@layouts.Base(meta.New("Notes", "..."), "")`

#### templates/pages/sign-in.templ

```templ
package pages

import (
    "$ARGUMENTS/templates/layouts"
    "$ARGUMENTS/templates/components/clerk"
    "$ARGUMENTS/internal/meta"
)

templ SignIn(m meta.PageMeta, clerkPublishableKey string) {
    @layouts.Base(m, clerkPublishableKey) {
        <div class="flex min-h-[60vh] items-center justify-center">
            @clerk.SignIn("/dashboard", "/sign-up")
        </div>
    }
}
```

#### templates/pages/sign-up.templ

```templ
package pages

import (
    "$ARGUMENTS/templates/layouts"
    "$ARGUMENTS/templates/components/clerk"
    "$ARGUMENTS/internal/meta"
)

templ SignUp(m meta.PageMeta, clerkPublishableKey string) {
    @layouts.Base(m, clerkPublishableKey) {
        <div class="flex min-h-[60vh] items-center justify-center">
            @clerk.SignUp("/dashboard", "/sign-in")
        </div>
    }
}
```

#### Update templates/pages/home.templ

Add client-side auth redirect as a fallback for authenticated users on the landing page:

```templ
import "$ARGUMENTS/templates/components/clerk"

templ Home(clerkPublishableKey string) {
    @layouts.Base(meta.PageMeta{Title: "Home"}, clerkPublishableKey) {
        @clerk.AuthRedirect("/dashboard")
        // ... existing home page content ...
    }
}
```

**Note:** Update the Home handler to pass `h.cfg.ClerkPublishableKey` when calling `pages.Home(key)`.

#### Update internal/handler/handler.go

Add Clerk auth routes:

```go
func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // ... existing static, health, public routes ...

    // Install Clerk auth middleware globally - verifies JWT and sets clerk_user_id
    e.Use(middleware.ClerkAuth(h.cfg.ClerkSecretKey))

    // Auth pages (public)
    e.GET("/sign-in", h.SignIn)
    e.GET("/sign-up", h.SignUp)

    // Protected routes - RequireClerkAuth checks for clerk_user_id set by ClerkAuth
    protected := e.Group("", middleware.RequireClerkAuth())
    protected.GET("/dashboard", h.Dashboard)
}
```

#### internal/handler/auth.go

```go
package handler

import (
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/templates/pages"

    "github.com/labstack/echo/v4"
)

func (h *Handler) SignIn(c echo.Context) error {
    m := meta.PageMeta{
        Title:       "Sign In",
        Description: "Sign in to your account",
    }
    return pages.SignIn(m, h.cfg.ClerkPublishableKey).Render(c.Request().Context(), c.Response().Writer)
}

func (h *Handler) SignUp(c echo.Context) error {
    m := meta.PageMeta{
        Title:       "Sign Up",
        Description: "Create a new account",
    }
    return pages.SignUp(m, h.cfg.ClerkPublishableKey).Render(c.Request().Context(), c.Response().Writer)
}
```

#### Clerk integration summary

| Method | Usage |
|--------|-------|
| `Clerk.mountSignIn(el, opts)` | Mount sign-in form |
| `Clerk.mountSignUp(el, opts)` | Mount sign-up form |
| `Clerk.mountUserButton(el)` | Mount user avatar/menu |
| `Clerk.user` | Current user object (null if not signed in) |
| `Clerk.session` | Current session object |

**Key options for mount methods:**
- `forceRedirectUrl` — guarantees redirect after auth (use instead of deprecated `afterSignInUrl`/`afterSignUpUrl`)
- `signUpUrl` / `signInUrl` — cross-links between sign-in and sign-up pages

**References:**
- https://clerk.com/docs/js-frontend/getting-started/quickstart
- https://clerk.com/docs/js-frontend/reference/components/authentication/sign-in
- https://clerk.com/docs/guides/development/customize-redirect-urls

### Deployment Files

Based on the deployment platform and build method selected:

**For Vercel:** Create `vercel.json`, `api/index.go`, and `public/` directory.

**For Nixpacks (Railway, Coolify, Dokploy, self-hosted with Nixpacks):**

Create `nixpacks.toml`:

```toml
[phases.setup]
nixpkgsArchive = 'a1bab9e494f5f4939442a57a58d0449a109593fe'
nixPkgs = ["go_1_25", "nodejs_20"]

[phases.install]
cmds = [
    "npm ci",
    "go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest",
    "go install github.com/a-h/templ/cmd/templ@latest",
]

[phases.build]
cmds = [
    "/root/go/bin/sqlc generate -f sqlc/sqlc.yaml",
    "/root/go/bin/templ generate",
    "npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --minify",
    "go build -o out ./cmd/server",
]

[start]
cmd = "./out"
```

**CRITICAL Nixpacks rules (learned the hard way):**

1. **Do NOT use `providers = ["go", "node"]`** — dual providers cause npm bash completion conflicts between auto-installed `nodejs_18` and your `nodejs_20`. Manage all packages manually via `nixPkgs` instead.
2. **Always use `nodejs_20`** — `nodejs_22` does NOT exist in most nixpkgs archives. Use `nodejs_20` or plain `nodejs`.
3. **Do NOT add `npm` to `nixPkgs`** — npm is bundled inside `nodejs_20`. Adding `"npm"` as a separate package will fail.
4. **Pin a nixpkgs archive with Go 1.25** — the default archive only has Go 1.22. Use archive `a1bab9e494f5f4939442a57a58d0449a109593fe` which has `go_1_25`. Find archive hashes at https://www.nixhub.io/packages/go.
5. **Use full paths for `go install` binaries in build phase** — `go install` puts binaries in `/root/go/bin/` which is NOT in `$PATH` during the build phase. Always use `/root/go/bin/sqlc`, `/root/go/bin/templ`.
6. **Separate install and build phases** — `go install` needs network access (install phase has it, build phase does not). Put `go install` commands in `[phases.install]`, not `[phases.build]`.
7. **Auto-detection doesn't work for dual-language projects** — Nixpacks sees `go.mod` and ignores `package.json`. You MUST explicitly install Node.js in `nixPkgs`.

If the project uses SQLite, add the SQLite Nix package:

```toml
[phases.setup]
nixpkgsArchive = 'a1bab9e494f5f4939442a57a58d0449a109593fe'
nixPkgs = ["go_1_25", "nodejs_20", "sqlite"]
```

**For Dokploy with SQLite:** Configure a persistent volume so the database survives deploys:

| Setting | Value |
|---------|-------|
| Mount Type | Volume Mount |
| Volume Name | `<project>-data` |
| Mount Path | `/app/data` |

The app's `DATABASE_URL` defaults to `data/<project>.db` which resolves to `/app/data/<project>.db` in the container.

**For Railway (with Nixpacks):** Also create `railway.toml` for Railway-specific config:

```toml
[build]
builder = "nixpacks"

[deploy]
healthcheckPath = "/health"
restartPolicyType = "on_failure"
restartPolicyMaxRetries = 3
```

**For Dockerfile (Fly.io, self-hosted, or user preference):**

Create a multi-stage `Dockerfile`:

```dockerfile
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git nodejs npm

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY package.json package-lock.json ./
RUN npm install

COPY . .

RUN go install github.com/a-h/templ/cmd/templ@latest && \
    templ generate && \
    npx @tailwindcss/cli -i static/css/input.css -o static/css/output.css --minify && \
    CGO_ENABLED=0 go build -o server ./cmd/server

FROM alpine:3.21

RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

COPY --from=builder /app/server .
COPY --from=builder /app/static ./static
COPY --from=builder /app/internal/database/migrations ./internal/database/migrations

EXPOSE 3000

CMD ["./server"]
```

If the project uses SQLite, the final stage needs the SQLite library and a volume for the database:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite
# ... same COPY lines ...
VOLUME /app/data
```

**For Fly.io:** Also create `fly.toml`:

```toml
app = "$ARGUMENTS"
primary_region = "ord"

[build]

[http_service]
  internal_port = 3000
  force_https = true

[[vm]]
  size = "shared-cpu-1x"
  memory = "256mb"
```

**For plain binary (self-hosted, no containers):**

No additional files needed. The Makefile already includes everything:
- `make dev` - Development with Air hot reload (logs to `tmp/air-combined.log`)
- `make build` - Build production binary
- `make run` - Build and run the server

For production, users run `make build` to create the binary, then deploy and run it directly (e.g., with systemd, supervisor, or a simple shell script).

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
   cd "./$ARGUMENTS"
   git init
   ```

2. **Install dependencies:**

   ```bash
   go mod tidy
   npm install
   ```

3. **Load environment variables:**

   The `.envrc` file was created with sensible defaults. Load it before any build/verification steps:

   ```bash
   # Check if direnv is installed and use it, otherwise source directly
   if command -v direnv &> /dev/null; then
       direnv allow
       eval "$(direnv export bash)"
   else
       # Source .envrc directly if direnv not installed
       set -a  # auto-export all variables
       source .envrc
       set +a
   fi
   ```

   **IMPORTANT:** This step is required before `make generate` or `make dev` will work, because the server requires DATABASE_URL to be set.

4. **Generate code:**

   ```bash
   make generate
   ```

5. **Verify the project builds and runs:**

   Before committing, verify everything works:

   ```bash
   # Build to check for compilation errors
   go build -o ./tmp/$ARGUMENTS ./cmd/server
   echo "✓ Build succeeded"

   # Quick start/stop test to verify DATABASE_URL is set correctly
   ./tmp/$ARGUMENTS &
   SERVER_PID=$!
   sleep 2

   # Check if server started (health endpoint)
   if curl -s http://localhost:${PORT:-3000}/health > /dev/null; then
       echo "✓ Server started successfully"
   else
       echo "✗ Server failed to start - check configuration"
   fi

   # Stop the test server
   kill $SERVER_PID 2>/dev/null || true
   ```

6. **Create initial commit:**

   ```bash
   git add .
   git commit -m "Initial project setup with Go + Templ + HTMX + Tailwind"
   ```

---

## Step 4: Implement Requested Functionality

**CRITICAL: Do not stop at scaffolding.** After the project structure is created, CONTINUE to implement what the user actually asked for.

### Analyze the User's Request

Parse `$ARGUMENTS` and earlier conversation context to determine:

1. **Domain entities** - What data does the app manage?
   - "notes app" → Note entity (title, content)
   - "todo app" → Task entity (title, completed, due_date)
   - "blog" → Post entity (title, content, published_at)
   - "inventory tracker" → Item entity (name, quantity, location)

2. **Operations needed** - Typically CRUD:
   - **C**reate - Add new records
   - **R**ead - List all, view single
   - **U**pdate - Edit existing
   - **D**elete - Remove records

3. **Special requirements** - Any features mentioned:
   - Search/filtering
   - Categories/tags
   - User ownership
   - Status workflows

### Generate Domain-Specific Files

For each identified entity, create these files (replace "example" with the actual entity):

#### 1. Update Migration (replace `001_initial.sql`)

Instead of the generic "examples" table, create the actual domain table:

**Example for a Notes app (SQLite):**
```sql
-- +goose Up
CREATE TABLE notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_notes_created_at ON notes(created_at DESC);

-- +goose Down
DROP TABLE IF EXISTS notes;
```

#### 2. Update SQL Queries (replace `sqlc/queries/example.sql`)

**Example for Notes (`sqlc/queries/notes.sql`):**
```sql
-- name: GetNote :one
SELECT * FROM notes WHERE id = ? LIMIT 1;

-- name: ListNotes :many
SELECT * FROM notes ORDER BY created_at DESC;

-- name: CreateNote :one
INSERT INTO notes (title, content) VALUES (?, ?) RETURNING *;

-- name: UpdateNote :exec
UPDATE notes SET title = ?, content = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?;

-- name: DeleteNote :exec
DELETE FROM notes WHERE id = ?;

-- name: SearchNotes :many
SELECT * FROM notes WHERE title LIKE ? OR content LIKE ? ORDER BY created_at DESC;
```

#### 3. Create Handler (`internal/handler/<entity>.go`)

**Example (`internal/handler/notes.go`):**
```go
package handler

import (
    "net/http"
    "strconv"

    "$ARGUMENTS/internal/database/sqlc"
    "$ARGUMENTS/templates/pages/notes"

    "github.com/labstack/echo/v4"
)

func (h *Handler) ListNotes(c echo.Context) error {
    ctx := c.Request().Context()
    notesList, err := h.db.Queries.ListNotes(ctx)
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to list notes")
    }
    return notes.List(notesList).Render(ctx, c.Response().Writer)
}

func (h *Handler) ShowNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    note, err := h.db.Queries.GetNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusNotFound, "note not found")
    }
    return notes.Show(note).Render(ctx, c.Response().Writer)
}

func (h *Handler) NewNote(c echo.Context) error {
    return notes.Form(nil).Render(c.Request().Context(), c.Response().Writer)
}

func (h *Handler) CreateNote(c echo.Context) error {
    ctx := c.Request().Context()
    title := c.FormValue("title")
    content := c.FormValue("content")

    if title == "" {
        return echo.NewHTTPError(http.StatusBadRequest, "title is required")
    }

    note, err := h.db.Queries.CreateNote(ctx, sqlc.CreateNoteParams{
        Title:   title,
        Content: &content,
    })
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to create note")
    }

    return c.Redirect(http.StatusSeeOther, "/notes/"+strconv.FormatInt(note.ID, 10))
}

func (h *Handler) EditNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    note, err := h.db.Queries.GetNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusNotFound, "note not found")
    }
    return notes.Form(&note).Render(ctx, c.Response().Writer)
}

func (h *Handler) UpdateNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    title := c.FormValue("title")
    content := c.FormValue("content")

    if title == "" {
        return echo.NewHTTPError(http.StatusBadRequest, "title is required")
    }

    err = h.db.Queries.UpdateNote(ctx, sqlc.UpdateNoteParams{
        ID:      id,
        Title:   title,
        Content: &content,
    })
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to update note")
    }

    return c.Redirect(http.StatusSeeOther, "/notes/"+strconv.FormatInt(id, 10))
}

func (h *Handler) DeleteNote(c echo.Context) error {
    ctx := c.Request().Context()
    id, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        return echo.NewHTTPError(http.StatusBadRequest, "invalid note ID")
    }

    err = h.db.Queries.DeleteNote(ctx, id)
    if err != nil {
        return echo.NewHTTPError(http.StatusInternalServerError, "failed to delete note")
    }

    // If HTMX request, return empty content for removal
    if c.Request().Header.Get("HX-Request") == "true" {
        return c.NoContent(http.StatusOK)
    }

    return c.Redirect(http.StatusSeeOther, "/notes")
}
```

#### 4. Register Routes (update `internal/handler/handler.go`)

Add routes in `RegisterRoutes`:
```go
// Notes routes
e.GET("/notes", h.ListNotes)
e.GET("/notes/new", h.NewNote)
e.POST("/notes", h.CreateNote)
e.GET("/notes/:id", h.ShowNote)
e.GET("/notes/:id/edit", h.EditNote)
e.PUT("/notes/:id", h.UpdateNote)
e.DELETE("/notes/:id", h.DeleteNote)
```

#### 5. Create Templates

**`templates/pages/notes/list.templ`:**
```templ
package notes

import (
    "$ARGUMENTS/internal/database/sqlc"
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/templates/layouts"
)

templ List(notes []sqlc.Note) {
    @layouts.Base(meta.New("Notes", "Manage your notes")) {
        <div class="flex justify-between items-center mb-6">
            <h1 class="text-2xl font-bold">Notes</h1>
            <a href="/notes/new" class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                New Note
            </a>
        </div>

        if len(notes) == 0 {
            <p class="text-muted-foreground">No notes yet. Create your first note!</p>
        } else {
            <div class="grid gap-4">
                for _, note := range notes {
                    @NoteCard(note)
                }
            </div>
        }
    }
}

templ NoteCard(note sqlc.Note) {
    <div id={ "note-" + strconv.FormatInt(note.ID, 10) } class="p-4 border border-border rounded-lg hover:border-primary transition-colors">
        <a href={ templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10)) }>
            <h2 class="font-semibold">{ note.Title }</h2>
            if note.Content != nil && *note.Content != "" {
                <p class="text-muted-foreground text-sm mt-1 line-clamp-2">{ *note.Content }</p>
            }
        </a>
    </div>
}
```

**`templates/pages/notes/show.templ`:**
```templ
package notes

import (
    "strconv"

    "$ARGUMENTS/internal/database/sqlc"
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/templates/layouts"
)

templ Show(note sqlc.Note) {
    @layouts.Base(meta.New(note.Title, "View note details")) {
        <div class="mb-6">
            <a href="/notes" class="text-muted-foreground hover:text-foreground">← Back to notes</a>
        </div>

        <article class="prose max-w-none">
            <h1>{ note.Title }</h1>
            if note.Content != nil {
                <p class="whitespace-pre-wrap">{ *note.Content }</p>
            }
        </article>

        <div class="mt-8 flex gap-4">
            <a href={ templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10) + "/edit") }
               class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                Edit
            </a>
            <button hx-delete={ "/notes/" + strconv.FormatInt(note.ID, 10) }
                    hx-confirm="Are you sure you want to delete this note?"
                    hx-target="body"
                    hx-push-url="/notes"
                    class="px-4 py-2 bg-destructive text-destructive-foreground rounded hover:bg-destructive/90">
                Delete
            </button>
        </div>
    }
}
```

**`templates/pages/notes/form.templ`:**
```templ
package notes

import (
    "strconv"

    "$ARGUMENTS/internal/database/sqlc"
    "$ARGUMENTS/internal/meta"
    "$ARGUMENTS/templates/layouts"
)

templ Form(note *sqlc.Note) {
    @layouts.Base(meta.New(formTitle(note), "Create or edit a note")) {
        <div class="mb-6">
            <a href="/notes" class="text-muted-foreground hover:text-foreground">← Back to notes</a>
        </div>

        <h1 class="text-2xl font-bold mb-6">{ formTitle(note) }</h1>

        <form method="POST" action={ formAction(note) } class="space-y-4 max-w-xl">
            if note != nil {
                <input type="hidden" name="_method" value="PUT"/>
            }

            <div>
                <label for="title" class="block text-sm font-medium mb-1">Title</label>
                <input type="text" id="title" name="title"
                       value={ formValue(note) }
                       required
                       class="w-full px-3 py-2 border border-border rounded focus:outline-none focus:ring-2 focus:ring-primary"/>
            </div>

            <div>
                <label for="content" class="block text-sm font-medium mb-1">Content</label>
                <textarea id="content" name="content" rows="10"
                          class="w-full px-3 py-2 border border-border rounded focus:outline-none focus:ring-2 focus:ring-primary">{ formContent(note) }</textarea>
            </div>

            <button type="submit"
                    class="px-4 py-2 bg-primary text-primary-foreground rounded hover:bg-primary/90">
                { submitLabel(note) }
            </button>
        </form>
    }
}

func formTitle(note *sqlc.Note) string {
    if note == nil {
        return "New Note"
    }
    return "Edit Note"
}

func formAction(note *sqlc.Note) templ.SafeURL {
    if note == nil {
        return "/notes"
    }
    return templ.SafeURL("/notes/" + strconv.FormatInt(note.ID, 10))
}

func formValue(note *sqlc.Note) string {
    if note == nil {
        return ""
    }
    return note.Title
}

func formContent(note *sqlc.Note) string {
    if note == nil || note.Content == nil {
        return ""
    }
    return *note.Content
}

func submitLabel(note *sqlc.Note) string {
    if note == nil {
        return "Create Note"
    }
    return "Update Note"
}
```

### Generate Tests

Create tests for each handler:

**`internal/handler/notes_test.go`:**
```go
package handler

import (
    "net/http"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"

    "$ARGUMENTS/internal/testutil"

    "github.com/labstack/echo/v4"
)

func TestListNotes(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    req := httptest.NewRequest(http.MethodGet, "/notes", nil)
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    if err := h.ListNotes(c); err != nil {
        t.Errorf("ListNotes() error = %v", err)
    }

    if rec.Code != http.StatusOK {
        t.Errorf("ListNotes() status = %d, want %d", rec.Code, http.StatusOK)
    }
}

func TestCreateNote(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    form := url.Values{}
    form.Add("title", "Test Note")
    form.Add("content", "Test content")

    req := httptest.NewRequest(http.MethodPost, "/notes", strings.NewReader(form.Encode()))
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    if err := h.CreateNote(c); err != nil {
        t.Errorf("CreateNote() error = %v", err)
    }

    if rec.Code != http.StatusSeeOther {
        t.Errorf("CreateNote() status = %d, want %d", rec.Code, http.StatusSeeOther)
    }
}

func TestCreateNote_EmptyTitle(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    form := url.Values{}
    form.Add("title", "")
    form.Add("content", "Test content")

    req := httptest.NewRequest(http.MethodPost, "/notes", strings.NewReader(form.Encode()))
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    err := h.CreateNote(c)
    if err == nil {
        t.Error("CreateNote() expected error for empty title, got nil")
    }
}
```

### Verify Implementation

After generating domain-specific code:

1. **Regenerate code:**
   ```bash
   go generate ./...
   ```

2. **Run tests:**
   ```bash
   go test -v ./...
   ```

3. **Build to verify compilation:**
   ```bash
   go build ./cmd/server
   ```

4. **Check for errors:**
   ```bash
   cat tmp/air-combined.log 2>/dev/null || echo "No log file yet"
   ```

**DO NOT STOP until:**
- ✅ All requested functionality is implemented (not just scaffolding)
- ✅ Database schema matches the domain
- ✅ CRUD handlers exist for each entity
- ✅ Templates render the UI
- ✅ Routes are registered
- ✅ Tests exist and pass
- ✅ Build succeeds

---

## Step 5: Display Summary

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

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. All project files are created (go.mod, main.go, handlers, templates, etc.)
2. Git repository is initialized with initial commit
3. `go mod tidy` succeeds
4. `npm install` succeeds
5. `go build ./cmd/server` succeeds without errors
6. Server starts successfully (health endpoint responds)

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the project will not be properly created.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
