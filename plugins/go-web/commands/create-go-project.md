---
argument-hint: "<project-name>"
description: "Create a new Go web project with Templ, HTMX, Tailwind, and sqlc"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(go:*)", "Bash(git:*)", "Bash(npm:*)", "Bash(npx:*)", "Bash(make:*)", "Bash(mkdir:*)", "Bash(touch:*)", "Bash(cd:*)", "Bash(curl:*)", "Bash(direnv:*)", "Bash(source:*)", "Bash(templ:*)", "Bash(templui:*)", "Bash(cat:*)", "Bash(kill:*)", "Bash(sleep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
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
!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "create-go-project-$ARGUMENTS" "COMPLETE"; fi`

## Security Validation

Before creating any files, validate the project name:

1. **Check for path traversal**: If `$ARGUMENTS` contains `/`, `..`, or starts with `.`, display error: "Project name cannot contain path separators or relative paths"
2. **Check for valid characters**: If `$ARGUMENTS` contains characters other than `a-z`, `A-Z`, `0-9`, `-`, or `_`, display error: "Project name must contain only alphanumeric characters, hyphens, and underscores"
3. **Check for reserved names**: If `$ARGUMENTS` is empty or matches system directories, display error

Only proceed if validation passes.

## Template Library

All static file templates for this command live in the plugin template library at
`${CLAUDE_PLUGIN_ROOT}/templates/`. The manifest listing every template and its target path is
`${CLAUDE_PLUGIN_ROOT}/templates/README.md`.

**How to use a template:** Read the template file, replace every occurrence of the placeholder
`{{PROJECT_NAME}}` with `$ARGUMENTS`, and Write the result to the target path inside
`./$ARGUMENTS/`. The Makefile additionally uses `{{DATABASE_TYPE}}` — replace it with
`postgres`, `sqlite3`, or `mysql` to match the selected database. Everything else in a template
is literal content (`${DATABASE_URL}`, `$(BINARY_NAME)`, and `${PORT:-3000}` are NOT
placeholders — write them verbatim). Preserve the Makefile's tab indentation exactly.

**Load only what you need:** per-database and per-option template variants are mutually
exclusive. Read ONLY the variant matching the user's choices (database, admin dashboard, Clerk,
deployment target). Never read variants for options the user did not select.

## Step 2: Create Project Structure

After gathering requirements, create the project at `./$ARGUMENTS/`.

### Core Files (always)

Copy each template (Read template → replace `{{PROJECT_NAME}}` → Write target). Create them in
this order (dependencies matter). `<db>` is the selected database: `postgres`, `sqlite`, or
`mysql`.

| Template (`${CLAUDE_PLUGIN_ROOT}/templates/`) | Target in `./$ARGUMENTS/` | Notes |
|---|---|---|
| core/go.mod | go.mod | Add the database driver and service SDK requires (see below) |
| core/gitignore | .gitignore | |
| env/envrc.example | .envrc.example | |
| env/envrc.`<db>` | .envrc | Working defaults for the selected database |
| core/package.json | package.json | |
| core/Makefile | Makefile | Replace `{{DATABASE_TYPE}}` with `postgres`, `sqlite3`, or `mysql`; keep tabs |
| core/air.toml | .air.toml | |
| core/golangci.yml | .golangci.yml | |
| db/sqlc.`<db>`.yaml | sqlc/sqlc.yaml | |
| db/queries-example.sql | sqlc/queries/example.sql | PostgreSQL `$1` params — adjust to `?` for SQLite/MySQL |
| db/migration-initial.`<db>`.sql | internal/database/migrations/001_initial.sql | |
| db/database.`<db>`.go | internal/database/database.go | |
| app/main.go | cmd/server/main.go | |
| app/server.go | cmd/server/server.go | |
| app/main_test.go | cmd/server/main_test.go | |
| app/slog.go | cmd/server/slog.go | |
| app/generate.go | cmd/server/generate.go | |
| app/config.go | internal/config/config.go | |
| app/ctxkeys.go | internal/ctxkeys/keys.go | |
| app/meta.go | internal/meta/meta.go | |
| app/meta-context.go | internal/meta/context.go | |
| app/middleware.go | internal/middleware/middleware.go | |
| app/handler.go | internal/handler/handler.go | |
| app/home.go | internal/handler/home.go | |
| app/testutil.<db>.go | internal/testutil/testutil.go | Select the helper matching the database backend |
| templ/meta.templ | templates/layouts/meta.templ | |
| templ/base.templ | templates/layouts/base.templ | |
| templ/home.templ | templates/pages/home.templ | |
| css/input.css OR css/input-templui.css | static/css/input.css | Use the templUI variant only if the admin dashboard was selected |
| ci/ci.yml | .github/workflows/ci.yml | Keep ONLY the `sqlc-vet` job variant for the selected database; delete the other two commented variants |
| ci/dependabot.yml | .github/dependabot.yml | |

**Database-specific `go.mod` additions:**

- PostgreSQL: `github.com/jackc/pgx/v5`, `github.com/google/uuid`
- SQLite: `modernc.org/sqlite` (CGO-free, pure Go)
- MySQL: `github.com/go-sql-driver/mysql`

**Also create:**

- `static/js/.gitkeep` — empty file to preserve the directory
- For SQLite projects only, the data directory:

```bash
mkdir -p data
touch data/.gitkeep
```

This ensures the database directory exists and is tracked by git (but not the database file
itself, which is in .gitignore).

### Admin Dashboard Files (if selected)

If the user selected Yes for admin dashboard, also create:

#### templates/layouts/admin.templ

Include the admin layout with:

- FOUC prevention script for dark mode
- Sidebar navigation
- Theme toggle
- Mobile responsive design

#### templates/components/theme/theme.templ

Dark/light mode toggle component with:

- Moon/sun icons
- localStorage persistence
- html.classList toggle

#### templates/components/sidebar/sidebar.templ

Collapsible sidebar with:

- Navigation sections
- Active state detection
- Mobile sheet integration

#### templates/pages/admin/dashboard.templ

Dashboard page with:

- Stats cards
- Quick actions
- Recent activity

#### internal/handler/admin.go

Admin route handlers.

#### static/css/input.css (templUI variant)

Use `${CLAUDE_PLUGIN_ROOT}/templates/css/input-templui.css` (already listed in the core files
table). It adds `@source "../../components/**/*.templ"` and the full set of templUI CSS
variables (including sidebar variables), and uses the Tailwind CSS v4 `@custom-variant dark`
syntax (NOT `@variant dark`).

After creating it, install the templUI CLI and the required components:

```bash
go install github.com/templui/templui@latest
templui add sidebar button card icon
```

Also uncomment `e.Static("/assets", "assets")` in `internal/handler/handler.go`.

#### templates/layouts/base.templ (templUI head changes)

When using templUI components, you MUST include their Script() templates in the `<head>`.
Read `${CLAUDE_PLUGIN_ROOT}/templates/templ/base-templui-head.templ` for the exact imports and
Script() calls to apply to `templates/layouts/base.templ`.

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

### Clerk Integration Files (if selected)

If the user selected Clerk, read `${CLAUDE_PLUGIN_ROOT}/references/clerk-integration.md` and
follow it completely. It covers the CRITICAL Clerk CDN rules, the file templates under
`${CLAUDE_PLUGIN_ROOT}/templates/auth/`, and the required updates to `.envrc`, config,
middleware/CSP, layouts, and routes. If Clerk was NOT selected, skip this entirely and do not
read that file.

### Deployment Files

Based on the deployment platform and build method selected, load ONLY the matching guidance:

| Selection | Action |
|---|---|
| Vercel + Neon | Create `vercel.json`, `api/index.go`, and a `public/` directory |
| Nixpacks (Railway, Coolify, Dokploy, self-hosted) | Read `${CLAUDE_PLUGIN_ROOT}/references/deployment/nixpacks.md` |
| Dockerfile (Fly.io, self-hosted, or user preference) | Read `${CLAUDE_PLUGIN_ROOT}/references/deployment/dockerfile.md` |
| Plain binary (self-hosted, no containers) | No additional files — the Makefile already covers `make dev`, `make build`, and `make run`; deploy the binary directly (systemd, supervisor, or a shell script) |

### Project Documentation

Create a `CLAUDE.md` in the project root following the content guide in
`${CLAUDE_PLUGIN_ROOT}/templates/docs/claude-md-guide.md`.

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

4. **Format generated Go files:**

   ```bash
   go fmt ./...
   ```

5. **Generate code:**

   ```bash
   make generate
   ```

6. **Verify the project builds and runs:**

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

For each identified entity, replace the generic `examples` scaffolding with real domain files:

1. Replace `internal/database/migrations/001_initial.sql` with the actual domain table(s) and indexes
2. Replace `sqlc/queries/example.sql` with per-entity queries (`sqlc/queries/<entity>.sql`)
3. Create `internal/handler/<entity>.go` with full CRUD handlers (HTMX-aware delete)
4. Register the entity routes in `internal/handler/handler.go`
5. Create list/show/form templates under `templates/pages/<entity>/`
6. Create `internal/handler/<entity>_test.go` covering list, create, and validation failures

For a complete worked example of all six files (a Notes app: migration, queries, handler,
routes, templ pages, and tests), read
`${CLAUDE_PLUGIN_ROOT}/references/crud-implementation-example.md` and adapt it to the actual
domain entities.

### Verify Implementation

After generating domain-specific code:

1. **Format generated Go files:**
   ```bash
   go fmt ./...
   ```

2. **Regenerate code:**
   ```bash
   go generate ./...
   ```

3. **Run tests:**
   ```bash
   go test -v ./...
   ```

4. **Build to verify compilation:**
   ```bash
   go build ./cmd/server
   ```

5. **Check for errors:**
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
