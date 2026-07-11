---
argument-hint: "[target-directory]"
description: "Convert an existing project to the Go + Templ + HTMX + Tailwind stack"
allowed-tools: ["Bash(*setup-loop.sh*)", "Bash(go:*)", "Bash(git:*)", "Bash(npm:*)", "Bash(npx:*)", "Bash(make:*)", "Bash(mkdir:*)", "Bash(touch:*)", "Bash(cd:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(curl:*)", "Bash(direnv:*)", "Bash(source:*)", "Bash(templ:*)", "Bash(templui:*)", "Bash(rg:*)", "Bash(fd:*)", "Bash(kill:*)", "Bash(sleep:*)", "Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion"]
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
!`if [ ! -x "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" ]; then echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."; exit 1; else "${CLAUDE_PLUGIN_ROOT}/scripts/setup-loop.sh" "convert-to-go-project" "COMPLETE"; fi`

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

Framework-specific migration guides live in `${CLAUDE_PLUGIN_ROOT}/references/migrations/`.
After detecting the source framework (Step 1), read ONLY the matching guide:

| Detected framework | Migration guide to read |
|---|---|
| Express.js / Fastify / other Node HTTP | `${CLAUDE_PLUGIN_ROOT}/references/migrations/express.md` |
| Django / Flask / FastAPI | `${CLAUDE_PLUGIN_ROOT}/references/migrations/django-flask.md` |
| Laravel / other PHP | `${CLAUDE_PLUGIN_ROOT}/references/migrations/laravel.md` |
| Next.js / React SPA | `${CLAUDE_PLUGIN_ROOT}/references/migrations/nextjs.md` |

Each guide covers route mapping, middleware and template conversion, ORM-to-sqlc query
migration, and that framework's meta/SEO migration patterns.

If the source project uses jQuery, React state, or other client-side JavaScript for UI
interactivity (dropdowns, modals, sidebars, tabs), also read
`${CLAUDE_PLUGIN_ROOT}/references/migrations/client-side-templui.md` for templUI conversion
patterns (including the critical rules for templ interpolation inside JavaScript).

If the detected framework has no guide, follow the "Unsupported Framework" flow in the Error
Handling section.

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

### Template Library

All static file templates live in the plugin template library at
`${CLAUDE_PLUGIN_ROOT}/templates/`. The manifest listing every template and its target path is
`${CLAUDE_PLUGIN_ROOT}/templates/README.md`.

**How to use a template:** Read the template file, replace every occurrence of the placeholder
`{{PROJECT_NAME}}` with the project/module name chosen for the conversion, and Write the result
to the target path in the project. The Makefile additionally uses `{{DATABASE_TYPE}}` — replace
it with `postgres`, `sqlite3`, or `mysql` to match the selected database. Everything else in a
template is literal content (`${DATABASE_URL}`, `$(BINARY_NAME)`, and `${PORT:-3000}` are NOT
placeholders — write them verbatim). Preserve the Makefile's tab indentation exactly.

**Load only what you need:** per-database and per-option template variants are mutually
exclusive. Read ONLY the variant matching the user's choices (database, admin dashboard /
templUI, Clerk, deployment target). Never read variants for options the user did not select.

### Core Files

Copy each template (Read template → replace `{{PROJECT_NAME}}` → Write target), following the
File Creation Order above. `<db>` is the selected database: `postgres`, `sqlite`, or `mysql`.
When merging into an existing project, append to (rather than overwrite) files that already
exist, such as `.gitignore` and `package.json`.

| Template (`${CLAUDE_PLUGIN_ROOT}/templates/`) | Target in project | Notes |
|---|---|---|
| core/go.mod | go.mod | Add the database driver and service SDK requires (see below) |
| core/gitignore | .gitignore | Append entries if a .gitignore already exists |
| env/envrc.example | .envrc.example | |
| env/envrc.`<db>` | .envrc | Working defaults for the selected database |
| core/package.json | package.json | Merge scripts/devDependencies if one already exists |
| core/Makefile | Makefile | Replace `{{DATABASE_TYPE}}` with `postgres`, `sqlite3`, or `mysql`; keep tabs |
| core/air.toml | .air.toml | |
| core/golangci.yml | .golangci.yml | |
| db/sqlc.`<db>`.yaml | sqlc/sqlc.yaml | |
| db/queries-example.sql | sqlc/queries/example.sql | PostgreSQL `$1` params — adjust to `?` for SQLite/MySQL; replace with queries from the existing schema |
| db/migration-initial.`<db>`.sql | internal/database/migrations/001_initial.sql | Replace the `examples` table with migrations generated from the existing schema |
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
| templ/base.templ | templates/layouts/base.templ | Recreate the original site's header/footer/layout structure here |
| templ/home.templ | templates/pages/home.templ | Replace the placeholder content with the converted home page |
| css/input.css OR css/input-templui.css | static/css/input.css | Use the templUI variant only if templUI components will be used |

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

**If using templUI components:** install the CLI
(`go install github.com/templui/templui@latest && templui add sidebar button card icon`),
uncomment `e.Static("/assets", "assets")` in `internal/handler/handler.go`, and apply the
`<head>` changes from `${CLAUDE_PLUGIN_ROOT}/templates/templ/base-templui-head.templ` to
`templates/layouts/base.templ` (component Script() templates are required — see the
client-side-templui migration guide).

### CI/CD and Quality Files

Check if CI/CD files already exist before creating:

```bash
# Check for existing CI configuration
ls -la .github/workflows/ .gitlab-ci.yml Jenkinsfile .circleci/ 2>/dev/null
```

**If CI exists:** Ask the user if they want to keep existing CI or replace with Go-specific workflow.

**If no CI exists:** Create the following files:

| Template (`${CLAUDE_PLUGIN_ROOT}/templates/`) | Target in project | Notes |
|---|---|---|
| ci/ci.yml | .github/workflows/ci.yml | Keep ONLY the `sqlc-vet` job variant for the selected database; delete the other two commented variants |
| ci/dependabot.yml | .github/dependabot.yml | Only if no dependabot config exists |

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

#### CLAUDE.md (only if no AI context file exists)

**Important:** Only create CLAUDE.md if no existing AI assistant context file was found during project analysis.

Check for these files first:
- `CLAUDE.md`
- `CLAUDE.local.md`
- `LLM.md`
- `AGENTS.md`
- `.claude/CLAUDE.md`

**If any exist:** Preserve the existing file. Inform the user: "Found existing AI context file: [filename]. Preserving it."

**If none exist:** Create a `CLAUDE.md` in the project root following the content guide in
`${CLAUDE_PLUGIN_ROOT}/templates/docs/claude-md-guide.md` (adjust the project name).

### SEO and Meta Tag Migration

**Key principle:** In Go, handlers do NOT construct meta. Templates own their meta.

The supporting files are already created from the template library in the Core Files table:
`internal/ctxkeys/keys.go`, `internal/meta/meta.go`, `internal/meta/context.go`, and
`templates/layouts/meta.templ`.

Before converting any templates, read
`${CLAUDE_PLUGIN_ROOT}/references/migrations/seo-preservation.md` for the metadata detection
commands, extraction checklist, site-wide config migration, OG image preservation, the per-page
migration pattern, and the preserved-metadata report format. Framework-specific meta migration
examples are in the framework guide you already loaded in Step 3.

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

Convert to goose migration format (`-- +goose Up` / `-- +goose Down`, as shown below).

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
7. **Run `go fmt ./...`** before verification
8. **Verify build and tests** before moving to next

### Generate Tests for Converted Handlers

For each converted handler, create `internal/handler/<entity>_test.go` using `testutil.NewTestDB`
and `testutil.NewTestConfig` with echo's `httptest` pattern. For a complete worked example
(handler + list/create/validation tests), read
`${CLAUDE_PLUGIN_ROOT}/references/crud-implementation-example.md` and adapt it to the converted
entities.

**Test at least:**
- List/index handlers return 200
- Show handlers return 200 for existing records, 404 for missing
- Create handlers validate input and return redirect on success
- Update handlers validate and return redirect
- Delete handlers return 200 or redirect

### Verification Checklist

After conversion, verify:

- [ ] `go fmt ./...` succeeds before generation, build, and test checks
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
4. `go fmt ./...` succeeds
5. `go mod tidy` succeeds
6. `go build ./cmd/server` succeeds without errors
7. `go test ./...` passes
8. Server starts and responds to requests

**When ALL criteria are met, output exactly:**

```
<done>COMPLETE</done>
```

This signals the loop to exit. If you output this prematurely, the conversion will not be complete.

---

**Safety note:** If you've iterated 15+ times without success, document what's blocking progress and ask the user for guidance.
