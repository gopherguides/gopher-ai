---
argument-hint: "[target-directory]"
description: "Convert an existing project to the Go + Templ + HTMX + Tailwind stack"
model: claude-opus-4-6
allowed-tools: ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
---

# Convert to Go Project

**If `$ARGUMENTS` is empty or not provided:**

This command converts an existing project to the Go + Templ + HTMX + Tailwind stack.

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

## Loop Initialization

Initialize persistent loop to ensure conversion completes fully:
!`"${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "convert-to-go-project" "COMPLETE"`

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
| `CLAUDE.md`, `LLM.md`, `AGENTS.md` | AI Context | Existing AI assistant instructions |

### Present Analysis Results

After scanning, present findings to the user:

```text
## Project Analysis Results

**Detected Technologies:**
- [List detected frameworks/languages]

**Database:**
- [Detected database type or "None detected"]

**AI Context Files:**
- [Found: CLAUDE.md / LLM.md / AGENTS.md] or "None found - will create CLAUDE.md"

**Existing Files to Preserve:**
- README.md
- .git/
- [AI context file if found]
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

### Client-Side Interactivity with templUI

templUI components handle client-side interactivity (dropdowns, modals, sidebars) via vanilla JavaScript
`Script()` templates. HTMX handles server communication. Together they replace heavy JavaScript frameworks.

**Important:** templUI does NOT use Alpine.js. Each interactive component has a `Script()` template that
must be included in your layout's `<head>`:

```templ
<head>
    @sidebar.Script()   // Required for: sidebar
    @dialog.Script()    // Required for: dialog, sheet, alertdialog
    @popover.Script()   // Required for: popover, dropdown, tooltip, combobox
    @accordion.Script() // Required for: accordion, collapsible
    @tabs.Script()      // Required for: tabs
</head>
```

**jQuery to templUI:**

```javascript
// jQuery (before)
$('.dropdown-toggle').click(function() {
  $(this).next('.dropdown-menu').toggle();
});
```

```templ
// templUI (after) - use dropdown component
@dropdown.Root() {
    @dropdown.Trigger() {
        <button>Toggle</button>
    }
    @dropdown.Content() {
        @dropdown.Item() { Option 1 }
        @dropdown.Item() { Option 2 }
    }
}
```

**React useState to templUI:**

```jsx
// React (before)
const [isOpen, setIsOpen] = useState(false);
return (
  <dialog open={isOpen}>...</dialog>
);
```

```templ
// templUI (after) - use dialog component
@dialog.Root() {
    @dialog.Trigger() {
        <button>Open Dialog</button>
    }
    @dialog.Content() {
        // Dialog content
    }
}
```

**Common templUI component patterns:**

| Pattern | templUI Component |
|---------|-------------------|
| Toggle visibility | `@dialog.Root()` with trigger/content |
| Dropdown menu | `@dropdown.Root()` |
| Sidebar navigation | `@sidebar.Root()` |
| Accordion/Collapsible | `@accordion.Root()` |
| Tabs | `@tabs.Root()` |
| Tooltip | `@tooltip.Root()` |
| Modal/Sheet | `@dialog.Root()` or `@sheet.Root()` |

> **CRITICAL: Templ Interpolation in JavaScript**
> Go expressions `{ value }` do NOT work inside `<script>` tags or inline event handler strings.
> - **Data attributes**: `data-id={ value }` + `this.dataset.id` in JS
> - **templ.JSFuncCall**: `onclick={ templ.JSFuncCall("fn", value) }` for onclick handlers
> - **Double braces**: `{{ value }}` (double braces) inside `<script>` tag strings
>
> If you see `%7B` or `%7D` in URLs, that's a literal `{` or `}` that wasn't interpolated.

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

#### .envrc (working environment file)

**IMPORTANT:** Also create the actual `.envrc` file with working defaults based on the selected database:

**For SQLite:**
```bash
# Environment configuration for [project-name]
# Automatically generated - modify as needed

# Database (SQLite)
export DATABASE_URL="./data/[project-name].db"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="[project-name]"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

**For PostgreSQL:**
```bash
# Environment configuration for [project-name]
# Automatically generated - modify DATABASE_URL with your credentials

# Database (PostgreSQL) - UPDATE WITH YOUR CREDENTIALS
export DATABASE_URL="postgres://localhost:5432/[project-name]?sslmode=disable"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="[project-name]"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

**For MySQL:**
```bash
# Environment configuration for [project-name]
# Automatically generated - modify DATABASE_URL with your credentials

# Database (MySQL) - UPDATE WITH YOUR CREDENTIALS
export DATABASE_URL="root@tcp(localhost:3306)/[project-name]"

# Server
export PORT="3000"
export ENV="development"
export LOG_LEVEL="DEBUG"

# Site / SEO
export SITE_NAME="[project-name]"
export SITE_URL="http://localhost:3000"
export DEFAULT_OG_IMAGE="/static/images/og-default.png"
```

#### data/.gitkeep (for SQLite projects only)

For SQLite projects, create the data directory:

```bash
mkdir -p data
touch data/.gitkeep
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

.PHONY: dev build test lint generate sqlc-vet css css-watch migrate migrate-down migrate-status migrate-create setup clean run help

BINARY_NAME=[project-name]
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

#### sqlc/sqlc.yaml

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

#### internal/database/migrations/001_initial.sql

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

#### cmd/server/generate.go

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

#### cmd/server/main.go

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

    "[project-name]/internal/config"
    "[project-name]/internal/database"
    "[project-name]/internal/handler"
    "[project-name]/internal/middleware"

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
    "embed"
    "fmt"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/jackc/pgx/v5/stdlib"
    "github.com/pressly/goose/v3"
    "[project-name]/internal/database/sqlc"
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
    "[project-name]/internal/database/sqlc"
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
    "[project-name]/internal/database/sqlc"
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

#### internal/middleware/middleware.go

```go
package middleware

import (
    "context"

    "[project-name]/internal/config"
    "[project-name]/internal/ctxkeys"

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
    // e.Static("/assets", "assets")  // Uncomment if using templUI components

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

**If using templUI components:**

When using templUI components, you MUST include their Script() templates in the `<head>`. Update base.templ to add the imports and Script() calls:

```templ
package layouts

import (
    "[project-name]/internal/meta"
    "[project-name]/components/sidebar"
    "[project-name]/components/dialog"
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
                <p class="text-muted-foreground text-sm">HTMX for server-driven interactivity.</p>
            </div>
        </div>
    }
}
```

### Static Files

#### static/css/input.css

Use the appropriate version based on whether you plan to use templUI components:

**Basic version (no templUI):**

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

**templUI version (if using templUI components):**

If you want to use templUI components, install the CLI first: `go install github.com/templui/templui@latest && templui add sidebar button card icon`

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

#### static/js/.gitkeep

Create empty file to preserve directory.

### CI/CD and Quality Files

Check if CI/CD files already exist before creating:

```bash
# Check for existing CI configuration
ls -la .github/workflows/ .gitlab-ci.yml Jenkinsfile .circleci/ 2>/dev/null
```

**If CI exists:** Ask the user if they want to keep existing CI or replace with Go-specific workflow.

**If no CI exists:** Create the following files:

#### .github/workflows/ci.yml

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
        run: go build -o bin/[project-name] ./cmd/server

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

#### .github/dependabot.yml (if no dependabot exists)

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

#### .golangci.yml

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

#### internal/testutil/testutil.go

```go
package testutil

import (
    "context"
    "testing"

    "[project-name]/internal/config"
    "[project-name]/internal/database"
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
            Name: "[project-name]",
            URL:  "http://localhost:3000",
        },
    }
}
```

**Note for PostgreSQL projects:** Modify `NewTestDB` to use a test database URL from environment variable `TEST_DATABASE_URL` or create a temporary test database.

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
    if cfg.ClerkSecretKey == "" {
        slog.Error("CLERK_SECRET_KEY environment variable is required")
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
    "github.com/clerk/clerk-sdk-go/v2"
    "github.com/clerk/clerk-sdk-go/v2/jwt"
)

// ClerkAuth verifies Clerk session tokens and sets user info in context.
// Pass cfg.ClerkSecretKey when creating the middleware.
func ClerkAuth(clerkSecretKey string) echo.MiddlewareFunc {
    // Configure Clerk SDK with the secret key for JWT verification
    clerk.SetKey(clerkSecretKey)

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
    if publishableKey != "" {
        @templ.Raw("<script async crossorigin=\"anonymous\" data-clerk-publishable-key=\"" + publishableKey + "\" src=\"https://cdn.jsdelivr.net/npm/@clerk/clerk-js@5/dist/clerk.browser.js\" type=\"text/javascript\"></script>")
    }
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
import "[project-name]/templates/components/clerk"

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
    "[project-name]/templates/layouts"
    "[project-name]/templates/components/clerk"
    "[project-name]/internal/meta"
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
    "[project-name]/templates/layouts"
    "[project-name]/templates/components/clerk"
    "[project-name]/internal/meta"
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
import "[project-name]/templates/components/clerk"

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
    "[project-name]/internal/meta"
    "[project-name]/templates/pages"

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
    "npm install",
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

# Copy package files (package-lock.json is optional)
COPY package.json package-lock.json* ./
RUN npm install

COPY . .

RUN go install github.com/a-h/templ/cmd/templ@latest && \
    go install github.com/sqlc-dev/sqlc/cmd/sqlc@latest && \
    sqlc generate -f sqlc/sqlc.yaml && \
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
app = "[project-name]"
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

#### CLAUDE.md (only if no AI context file exists)

**Important:** Only create CLAUDE.md if no existing AI assistant context file was found during project analysis.

Check for these files first:
- `CLAUDE.md`
- `CLAUDE.local.md`
- `LLM.md`
- `AGENTS.md`
- `.claude/CLAUDE.md`

**If any exist:** Preserve the existing file. Inform the user: "Found existing AI context file: [filename]. Preserving it."

**If none exist:** Create a CLAUDE.md file with the following content (adjust project name):

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
5. **Load environment variables:**

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

6. **Generate tests** for converted handlers
7. **Verify build and tests** before moving to next

### Generate Tests for Converted Handlers

For each converted handler, create tests following this pattern:

**`internal/handler/<entity>_test.go`:**

```go
package handler

import (
    "net/http"
    "net/http/httptest"
    "testing"

    "[project-name]/internal/testutil"

    "github.com/labstack/echo/v4"
)

func TestList<Entity>(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    req := httptest.NewRequest(http.MethodGet, "/<entities>", nil)
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    if err := h.List<Entity>(c); err != nil {
        t.Errorf("List<Entity>() error = %v", err)
    }

    if rec.Code != http.StatusOK {
        t.Errorf("List<Entity>() status = %d, want %d", rec.Code, http.StatusOK)
    }
}

func TestCreate<Entity>(t *testing.T) {
    t.Parallel()

    db := testutil.NewTestDB(t)
    cfg := testutil.NewTestConfig(t)
    h := New(cfg, db)

    e := echo.New()
    // Add form data or JSON body
    req := httptest.NewRequest(http.MethodPost, "/<entities>", nil)
    req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
    rec := httptest.NewRecorder()
    c := e.NewContext(req, rec)

    // Test creation logic
    // ...
}
```

**Test at least:**
- List/index handlers return 200
- Show handlers return 200 for existing records, 404 for missing
- Create handlers validate input and return redirect on success
- Update handlers validate and return redirect
- Delete handlers return 200 or redirect

### Verification Checklist

After conversion, verify:

- [ ] `make dev` starts the server
- [ ] All routes respond correctly
- [ ] Database queries work
- [ ] Templates render properly
- [ ] Static assets load
- [ ] Forms submit successfully
- [ ] No Go expressions in `<script>` tags (use data attributes instead)
- [ ] `go test -v ./...` passes
- [ ] `golangci-lint run` passes
- [ ] CI workflow runs successfully

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

---

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these conditions are TRUE:**

1. Go project structure is created alongside existing files
2. All migrations are created from existing schema
3. Core handlers and templates are converted
4. `go mod tidy` succeeds
5. `go build ./cmd/server` succeeds without errors
6. `go test ./...` passes
7. Server starts and responds to requests

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the conversion will not be complete.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
