---
argument-hint: "[target-directory]"
description: "Convert an existing project to the Go + Templ + HTMX + Alpine.js + Tailwind stack"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Convert to Go Project

**If `$ARGUMENTS` is empty or not provided:**

This command converts an existing project to the Go + Templ + HTMX + Alpine.js + Tailwind stack.

It will analyze your current project, identify what can be preserved, and incrementally
add Go stack files while migrating your existing logic.

**Usage:** `/convert-to-go-project [target-directory]`

**Examples:**

- `/convert-to-go-project` - Convert current directory
- `/convert-to-go-project ./my-project` - Convert specific directory

**Workflow:**

1. Analyze existing project structure and technologies
2. Ask about conversion scope (full vs. incremental)
3. Ask database and service preferences
4. Create Go project structure alongside existing files
5. Migrate routes, handlers, and templates
6. Provide migration guidance for remaining code

Proceed to analyze the current directory.

---

**If `$ARGUMENTS` is provided:**

Convert the project at `$ARGUMENTS` (or current directory if `.`) to the Go stack.

## Step 1: Project Analysis

Scan the target directory to detect existing technologies.

### Detection Checks

Run these checks to identify the current stack:

| File/Pattern | Technology | Detection Command |
|--------------|------------|-------------------|
| `package.json` | Node.js | Check for express, fastify, next, etc. |
| `requirements.txt` or `pyproject.toml` | Python | Check for django, flask, fastapi |
| `composer.json` | PHP | Check for laravel, symfony |
| `go.mod` | Go (existing) | Already Go - extend rather than convert |
| `Gemfile` | Ruby | Check for rails, sinatra |
| `*.sql` or `schema.prisma` | Database schema | Existing database structure |
| `Dockerfile` | Docker | Container configuration |
| `.env` or `.envrc` | Environment | Existing configuration |

### Present Analysis Results

After scanning, present findings to the user:

```text
## Project Analysis Results

**Detected Technologies:**
- [List detected frameworks/languages]

**Database:**
- [Detected database type or "None detected"]

**Existing Files to Preserve:**
- README.md
- .git/
- [Other important files]

**Files to Migrate:**
- [Routes/controllers]
- [Templates/views]
- [Database models]

**Files to Replace:**
- [Framework-specific config]
```

Ask the user to confirm the analysis is correct.

---

## Step 2: Gather Conversion Requirements

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

Use AskUserQuestion for each of these:

### Conversion Scope

| Option | Description |
|--------|-------------|
| **Full conversion** | Replace entire stack with Go |
| **Incremental** | Add Go alongside existing code |
| **Backend only** | Convert backend, keep frontend as-is |

**Plain explanations:**

- **Full conversion**: Best for smaller projects. We'll convert everything at once -
  routes, templates, database queries. Old framework files will be removed.

- **Incremental**: Best for larger projects. We'll add Go files alongside your existing
  code. You can run both during transition and migrate piece by piece.

- **Backend only**: Keep your frontend (React, Vue, etc.) and just convert the API
  to Go. Good if you have a separate frontend app.

### Database Selection

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

| Option | Description |
|--------|-------------|
| **Yes** | Include admin UI with dark/light mode |
| **No** | Skip admin UI |

### Deployment Platform

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

## Step 3: Migration Strategy

Based on the detected framework, provide specific migration guidance.

### Express.js to Echo

**Route Mapping:**

```javascript
// Express (before)
router.get('/users', usersController.list);
router.post('/users', usersController.create);
router.get('/users/:id', usersController.show);
router.put('/users/:id', usersController.update);
router.delete('/users/:id', usersController.delete);
```

```go
// Echo (after)
e.GET("/users", h.UserList)
e.POST("/users", h.UserCreate)
e.GET("/users/:id", h.UserShow)
e.PUT("/users/:id", h.UserUpdate)
e.DELETE("/users/:id", h.UserDelete)
```

**Middleware Conversion:**

```javascript
// Express middleware
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));
```

```go
// Echo middleware
e.Use(middleware.CORS())
e.Use(middleware.Logger())
e.Use(middleware.Recover())
```

**Controller to Handler:**

```javascript
// Express controller
exports.list = async (req, res) => {
  const users = await User.findAll();
  res.json(users);
};
```

```go
// Go handler
func (h *Handler) UserList(c echo.Context) error {
    ctx := c.Request().Context()
    users, err := h.db.Queries.ListUsers(ctx)
    if err != nil {
        return err
    }
    return c.JSON(http.StatusOK, users)
}
```

### Django/Flask to Go

**URL Patterns:**

```python
# Django
urlpatterns = [
    path('users/', views.user_list, name='user_list'),
    path('users/<int:pk>/', views.user_detail, name='user_detail'),
]

# Flask
@app.route('/users')
def user_list():
    ...
```

```go
// Echo
e.GET("/users", h.UserList)
e.GET("/users/:id", h.UserDetail)
```

**Django Template to Templ:**

```django
{% extends "base.html" %}
{% block content %}
  <h1>{{ user.name }}</h1>
  {% for post in posts %}
    <article>{{ post.title }}</article>
  {% endfor %}
{% endblock %}
```

```templ
package pages

import "myapp/templates/layouts"

templ UserDetail(user User, posts []Post) {
    @layouts.Base("User") {
        <h1>{ user.Name }</h1>
        for _, post := range posts {
            <article>{ post.Title }</article>
        }
    }
}
```

**Django Model to goose Migration:**

```python
# Django model
class User(models.Model):
    email = models.EmailField(unique=True)
    name = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)
```

```sql
-- goose migration
-- +goose Up
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- +goose Down
DROP TABLE IF EXISTS users;
```

### Laravel to Go

**Route Mapping:**

```php
// Laravel
Route::get('/users', [UserController::class, 'index']);
Route::post('/users', [UserController::class, 'store']);
Route::get('/users/{user}', [UserController::class, 'show']);
```

```go
// Echo
e.GET("/users", h.UserIndex)
e.POST("/users", h.UserStore)
e.GET("/users/:id", h.UserShow)
```

**Blade to Templ:**

```blade
@extends('layouts.app')

@section('content')
    <h1>{{ $user->name }}</h1>
    @foreach($posts as $post)
        <article>{{ $post->title }}</article>
    @endforeach
@endsection
```

```templ
package pages

import "myapp/templates/layouts"

templ UserShow(user User, posts []Post) {
    @layouts.Base("User") {
        <h1>{ user.Name }</h1>
        for _, post := range posts {
            <article>{ post.Title }</article>
        }
    }
}
```

**Eloquent to sqlc:**

```php
// Laravel Eloquent
$users = User::where('active', true)->orderBy('name')->get();
```

```sql
-- sqlc query
-- name: ListActiveUsers :many
SELECT * FROM users WHERE active = true ORDER BY name;
```

### Next.js to Go + HTMX

**API Routes:**

```javascript
// Next.js API route (pages/api/users.js)
export default async function handler(req, res) {
  if (req.method === 'GET') {
    const users = await prisma.user.findMany();
    res.json(users);
  }
}
```

```go
// Go handler
func (h *Handler) UserList(c echo.Context) error {
    users, err := h.db.Queries.ListUsers(c.Request().Context())
    if err != nil {
        return err
    }
    return c.JSON(http.StatusOK, users)
}
```

**React Component to Templ + HTMX:**

```jsx
// React with fetch
function UserList() {
  const [users, setUsers] = useState([]);
  useEffect(() => {
    fetch('/api/users').then(r => r.json()).then(setUsers);
  }, []);
  return <ul>{users.map(u => <li key={u.id}>{u.name}</li>)}</ul>;
}
```

```templ
// Templ with HTMX
templ UserList(users []User) {
    <ul hx-get="/users" hx-trigger="load" hx-swap="innerHTML">
        for _, user := range users {
            <li>{ user.Name }</li>
        }
    </ul>
}
```

### Client-Side JavaScript to Alpine.js

Alpine.js handles client-side interactivity (dropdowns, modals, tabs) while HTMX handles
server communication. Together they replace heavy JavaScript frameworks.

**jQuery to Alpine.js:**

```javascript
// jQuery (before)
$('.dropdown-toggle').click(function() {
  $(this).next('.dropdown-menu').toggle();
});
```

```html
<!-- Alpine.js (after) -->
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open" x-transition>Dropdown content</div>
</div>
```

**React useState to Alpine.js:**

```jsx
// React (before)
const [isOpen, setIsOpen] = useState(false);
return (
  <div>
    <button onClick={() => setIsOpen(!isOpen)}>Toggle</button>
    {isOpen && <div>Content</div>}
  </div>
);
```

```html
<!-- Alpine.js (after) -->
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open" x-transition>Content</div>
</div>
```

**Vue v-model to Alpine.js:**

```html
<!-- Vue (before) -->
<input v-model="search" />
<p>Searching for: {{ search }}</p>
```

```html
<!-- Alpine.js (after) -->
<div x-data="{ search: '' }">
  <input x-model="search" />
  <p>Searching for: <span x-text="search"></span></p>
</div>
```

**Common Alpine.js patterns:**

| Pattern | Alpine.js |
|---------|-----------|
| Toggle visibility | `x-show="open"` with `@click="open = !open"` |
| Conditional render | `x-if="condition"` (removes from DOM) |
| Loop | `x-for="item in items"` |
| Bind attribute | `:class="{ active: isActive }"` |
| Two-way binding | `x-model="value"` |
| Event listener | `@click`, `@submit.prevent`, `@keydown.escape` |
| Transitions | `x-transition` or `x-transition.duration.300ms` |

---

## Step 4: Create Go Project Structure

Add Go files to the project. Create the same structure as `/create-go-project`:

```text
[existing-project]/
├── cmd/server/           # NEW
├── internal/             # NEW
├── templates/            # NEW (migrate existing views)
├── migrations/           # NEW (from existing schema)
├── sqlc/                 # NEW
├── static/               # KEEP or merge with existing
├── .air.toml             # NEW
├── Makefile              # NEW
├── go.mod                # NEW
├── [existing files]      # PRESERVE during transition
```

### File Creation Order

1. **Foundation files:** go.mod, .gitignore additions, .air.toml, Makefile
2. **Configuration:** internal/config/config.go, sqlc/sqlc.yaml
3. **Database:** internal/database/database.go, migrations (from existing schema)
4. **SEO/Meta:** internal/meta/meta.go, templates/layouts/meta.templ
5. **Core Go:** internal/middleware, internal/handler
6. **Templates:** Convert existing views to Templ (including meta integration)
7. **Entry point:** cmd/server/main.go, cmd/server/slog.go
8. **Documentation:** CLAUDE.md for AI assistant guidance

### Core Files

Create these files in order (dependencies matter):

#### go.mod

```go
module [project-name]

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

#### .gitignore

```text
# Binaries
[project-name]
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

#### .envrc.example

```bash
# Copy this file to .envrc and edit with your values
# Then run: direnv allow

# Database
# PostgreSQL: postgres://user:pass@localhost:5432/dbname?sslmode=disable
# SQLite: ./data/[project-name].db
# MySQL: user:pass@tcp(localhost:3306)/dbname
export DATABASE_URL="YOUR_DATABASE_URL_HERE"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO (used for meta tags, OG, etc.)
export SITE_NAME="[project-name]"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"

# CLERK_SECRET_KEY and CLERK_PUBLISHABLE_KEY if Clerk selected
# BREVO_API_KEY if Brevo selected
# STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY, STRIPE_WEBHOOK_SECRET if Stripe selected
```

#### package.json

```json
{
  "name": "[project-name]",
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

#### Makefile

```makefile
SHELL := /bin/bash

.PHONY: dev build test lint generate css css-watch migrate migrate-down migrate-status migrate-create setup clean run help

BINARY_NAME=[project-name]
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

#### .air.toml

```toml
root = "."
testdata_dir = "testdata"
tmp_dir = "tmp"

[build]
  args_bin = []
  bin = "./tmp/[project-name]"
  cmd = "go build -o ./tmp/[project-name] ./cmd/server"
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

#### sqlc/sqlc.yaml

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

#### sqlc/queries/example.sql

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

#### migrations/001_initial.sql

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

#### cmd/server/slog.go

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

#### cmd/server/main.go

```go
package main

import (
    "context"
    "log/slog"
    "os"
    "os/signal"
    "syscall"
    "time"

    "[project-name]/internal/config"
    "[project-name]/internal/database"
    "[project-name]/internal/handler"
    "[project-name]/internal/middleware"

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

#### internal/config/config.go

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
            Name:           getEnvOrDefault("SITE_NAME", "[project-name]"),
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

#### internal/database/database.go

**For PostgreSQL:**

```go
package database

import (
    "context"
    "fmt"

    "github.com/jackc/pgx/v5/pgxpool"
    "[project-name]/internal/database/sqlc"
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
    "[project-name]/internal/database/sqlc"
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
    "[project-name]/internal/database/sqlc"
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

#### internal/middleware/middleware.go

```go
package middleware

import (
    "context"
    "log/slog"
    "time"

    "[project-name]/internal/config"
    "[project-name]/internal/ctxkeys"

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

#### internal/handler/handler.go

```go
package handler

import (
    "[project-name]/internal/config"
    "[project-name]/internal/database"

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

#### internal/handler/home.go

Handlers do NOT construct meta - that's the template's job:

```go
package handler

import (
    "net/http"

    "[project-name]/templates/pages"

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

#### templates/layouts/meta.templ

Meta tags component - site name comes from context, not the struct:

```templ
package layouts

import "[project-name]/internal/meta"

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

#### templates/layouts/base.templ

Base layout receives meta from the page template, not the handler:

```templ
package layouts

import "[project-name]/internal/meta"

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

#### templates/pages/home.templ

Template constructs its own meta - handler doesn't pass it:

```templ
package pages

import (
    "[project-name]/internal/meta"
    "[project-name]/templates/layouts"
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

#### static/css/input.css

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

#### static/js/.gitkeep

Create empty file to preserve directory.

### Deployment Files

Based on the deployment platform selected:

**For Vercel:** Create `vercel.json`, `api/index.go`, and `public/` directory.

**For Railway:** Create `railway.toml`.

**For Fly.io:** Create `fly.toml` and `Dockerfile`.

**For Self-hosted:** Create `Dockerfile` only.

### Project Documentation

#### CLAUDE.md

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

### SEO and Meta Tag Migration

**Key principle:** In Go, handlers do NOT construct meta. Templates own their meta.

#### Create Files for SEO

1. `internal/ctxkeys/keys.go` - Typed context keys
2. `internal/meta/meta.go` - PageMeta struct
3. `internal/meta/context.go` - Context helpers (SiteNameFromCtx)
4. `templates/layouts/meta.templ` - Meta tag component

#### internal/ctxkeys/keys.go

```go
package ctxkeys

type siteConfigKey struct{}

var SiteConfig = siteConfigKey{}
```

#### internal/meta/meta.go

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

func (m PageMeta) AsArticle() PageMeta {
    m.OGType = "article"
    return m
}

func (m PageMeta) AsProduct() PageMeta {
    m.OGType = "product"
    return m
}
```

#### internal/meta/context.go

```go
package meta

import (
    "context"
    "yourapp/internal/config"
    "yourapp/internal/ctxkeys"
)

func SiteFromCtx(ctx context.Context) config.SiteConfig {
    if cfg, ok := ctx.Value(ctxkeys.SiteConfig).(config.SiteConfig); ok {
        return cfg
    }
    return config.SiteConfig{Name: "MyApp"}
}

func SiteNameFromCtx(ctx context.Context) string {
    return SiteFromCtx(ctx).Name
}
```

#### Framework-Specific Migration

**From Next.js (handler passes meta):**

```jsx
// Next.js (before)
export const metadata = {
  title: 'My Page',
  description: 'Page description',
};
```

```templ
// Go template (after) - template constructs meta
templ MyPage() {
    @layouts.Base(meta.New("My Page", "Page description")) {
        // content
    }
}
```

**From Django (template blocks):**

```django
{% raw %}
{% block meta %}
<title>{{ page_title }}</title>
<meta name="description" content="{{ page_description }}">
{% endblock %}
{% endraw %}
```

```templ
// Go template (after)
templ MyPage() {
    @layouts.Base(meta.New("Page Title", "Page description")) {
        // content
    }
}
```

**From Laravel (controller passes vars):**

```php
// Laravel (before)
return view('page', ['title' => 'My Page']);
```

```go
// Go handler (after) - does NOT pass meta
func (h *Handler) Page(c echo.Context) error {
    return pages.Page().Render(c.Request().Context(), c.Response().Writer)
}
```

```templ
// Go template - owns its meta
templ Page() {
    @layouts.Base(meta.New("My Page", "Description")) {
        // content
    }
}
```

**From Express (res.render with vars):**

```javascript
// Express (before)
res.render('page', { title: 'My Page' });
```

```go
// Go handler (after) - clean, no meta
func (h *Handler) Page(c echo.Context) error {
    return pages.Page().Render(c.Request().Context(), c.Response().Writer)
}
```

#### Migrating Site-Wide Config

Move hardcoded site names to environment variables:

```bash
# .envrc
export SITE_NAME="My App"
export SITE_URL="https://example.com"
```

Middleware injects into context, templates access via `meta.SiteNameFromCtx(ctx)`.

#### Preserve Existing OG Images

When converting, identify and preserve existing OG images:

1. Check `public/`, `static/`, `assets/` for og-*.png files
2. Copy to Go project's `static/images/` directory
3. Reference in templates: `meta.New("Title", "Desc").WithOGImage("/static/images/og.png")`

### Database Schema Migration

If the project has an existing database:

1. Export current schema
2. Convert to goose migration format
3. Create sqlc queries from existing SQL or ORM code

**From Prisma schema:**

```prisma
model User {
  id        String   @id @default(uuid())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
}
```

Convert to goose migration (see Django example above).

**From existing SQL files:**

Copy and wrap with goose markers:

```sql
-- +goose Up
[existing CREATE TABLE statements]

-- +goose Down
[DROP TABLE statements in reverse order]
```

### What Gets Preserved During Conversion

This conversion PRESERVES the following from the original site:

| Element | What's Preserved | How |
|---------|------------------|-----|
| **Visual Design** | CSS, colors, typography, spacing | Extract styles to Tailwind classes |
| **Layout Structure** | Header, footer, sidebar positions | Recreate in base.templ layout |
| **Content** | All text, images, data | Copy directly to Go templates |
| **Navigation** | Routes and URL structure | Map to Echo routes (same URLs) |
| **SEO Elements** | Meta tags, OG images, structured data | Migrate to meta.PageMeta |
| **Assets** | Images, fonts, icons | Copy to static/ directory |

**Critical:** Preserve the same URL structure. If the old site has `/about`, the Go site
must also have `/about`. Do NOT change routes during conversion.

### SEO/Metadata Preservation

Before converting templates, scan the existing project for all SEO-related content.

#### Metadata Detection Commands

```bash
# Search for meta tags in templates
rg -i '<meta\s+' --glob '*.html' --glob '*.jsx' --glob '*.vue' --glob '*.blade.php' --glob '*.erb' --glob '*.twig'

# Search for OG tags
rg 'og:' --glob '*.html' --glob '*.jsx' --glob '*.vue'

# Search for JSON-LD structured data
rg 'application/ld\+json' --glob '*.html' --glob '*.jsx'

# Search for existing SEO config files
fd -e json -e yaml -e yml | xargs rg -l 'seo\|meta\|og:'
```

#### Metadata to Extract

Scan for these elements:

- **Title tags**: Extract page titles from templates/views
- **Meta descriptions**: Find description meta tags
- **OG tags**: og:title, og:description, og:image, og:type, og:url
- **Twitter cards**: twitter:card, twitter:title, twitter:description, twitter:image
- **Canonical URLs**: link rel="canonical"
- **Structured data**: JSON-LD, microdata
- **Robots directives**: noindex, nofollow
- **Sitemap references**: sitemap.xml locations
- **Favicon/icons**: Various icon formats and sizes

#### Framework-Specific SEO Extraction

**Next.js:**

```javascript
// Look for these patterns
export const metadata = { ... }
generateMetadata()
<Head>...</Head>
```

**Django:**

```python
# Look for these patterns
{% block meta %}
{{ page.seo_title }}
```

**Laravel:**

```php
// Look for SEO packages
@section('meta')
SEO::setTitle()
```

#### Migration Pattern

When converting each page/template:

1. **Extract metadata from source**:
   - Parse the original template for all meta-related content
   - Document any dynamic metadata (e.g., `{{ page.title }}`)
   - Note any SEO-related environment variables

2. **Map to Go/Templ structure**:
   - Static metadata → Direct in template via `meta.New()`
   - Dynamic metadata → Handler passes data, template constructs meta
   - Site-wide metadata → Context via middleware

3. **Preserve OG images**:
   - Find existing OG image files
   - Copy to `static/images/`
   - Update paths in templates

4. **Report preserved metadata**:

After conversion, display a summary:

```text
## SEO Metadata Preserved

| Page | Title | Description | OG Image |
|------|-------|-------------|----------|
| /    | Home  | Welcome...  | /static/images/og-home.png |
| /about | About Us | Learn... | /static/images/og-default.png |
```

---

## Step 5: Incremental Migration Plan

For large projects, suggest this phased approach:

### Phase 1: Foundation (Day 1)

- Add Go project structure alongside existing code
- Set up shared database connection
- Create base templates
- Configure Air hot reload

Both apps can run simultaneously:

- Existing app: port 3000
- Go app: port 3000

### Phase 2: Static Pages (Days 2-3)

- Convert static/simple pages to Templ
- Add Tailwind CSS
- Set up HTMX for simple interactions

### Phase 3: Core Features (Days 4-7)

- Convert main CRUD operations
- Migrate database queries to sqlc
- Add authentication middleware (if using Clerk)

### Phase 4: Cleanup (Day 8+)

- Remove old framework files
- Update deployment configuration
- Update documentation

---

## Step 6: Execute Conversion

After planning, execute the conversion:

1. **Create Go structure** without removing existing files
2. **Generate migrations** from existing database schema
3. **Convert templates** one at a time
4. **Migrate routes** starting with simplest endpoints
5. **Test each conversion** before moving to next

### Verification Checklist

After conversion, verify:

- [ ] `make dev` starts the server
- [ ] All routes respond correctly
- [ ] Database queries work
- [ ] Templates render properly
- [ ] Static assets load
- [ ] Forms submit successfully

---

## Step 7: Display Summary

After conversion, display a summary to the user showing:

**Conversion Complete Header:**

- Project name
- Converted from: [detected framework]
- Conversion type: full/incremental/backend-only

**Files Created Table:**

| Category | Count |
|----------|-------|
| Go source files | X |
| Templ templates | X |
| Migrations | X |
| Config files | X |

**Files Preserved:**

List the files that were preserved (README, .git, etc.)

**Files to Remove (after testing):**

List old framework files that can be safely removed after verification.

**Next Steps:**

1. Test the Go app: `make dev`
1. Verify routes: Visit each page and test functionality
1. Run tests: `make test`
1. Remove old files (when ready): `rm -rf [old-framework-files]`
1. Update deployment: Follow deployment instructions for your platform

**Migration Notes:**

Include any specific notes about the conversion, pending items, or manual steps needed.

---

## Error Handling

If conversion encounters issues:

### Unsupported Framework

If the detected framework isn't in the migration guides:

```text
I detected [framework] which doesn't have a specific migration guide yet.

Would you like me to:
1. Attempt a general conversion (analyze your code and convert patterns)
2. Stop and let you provide more context about your project

The general conversion will:
- Analyze your route definitions
- Convert controllers/views to Go handlers
- Migrate templates to Templ syntax
- Create database migrations from your schema
```

### Complex ORM Queries

If the project uses complex ORM queries that don't map directly to SQL:

```text
I found some complex ORM patterns that need manual review:

[Example query]

This query uses [feature] which doesn't have a direct SQL equivalent.

Options:
1. Convert to multiple simpler queries
2. Keep as a raw SQL query with manual implementation
3. Skip for now and add TODO comment

Which approach would you prefer?
```

### Frontend-Heavy Projects

If the project is heavily frontend-focused (SPA):

```text
This appears to be a frontend-heavy project with [framework].

For projects with complex frontend logic, consider:
1. **Keep frontend, convert API only** - Your [React/Vue/etc] app stays the same,
   only the backend becomes Go
2. **Progressive enhancement** - Convert to HTMX gradually, keeping some React
   components where needed
3. **Full conversion** - Replace everything with Templ + HTMX (significant rewrite)

Which approach fits your needs?
```
