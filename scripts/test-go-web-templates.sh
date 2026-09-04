#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/plugins/go-web/templates"
CONVERSION_COMMAND="$ROOT_DIR/plugins/go-web/commands/convert-to-go-project.md"
CONVERSION_SKILL="$ROOT_DIR/plugins/go-web/skills/convert-to-go-project/SKILL.md"
CONVERSION_WORKFLOW="$ROOT_DIR/plugins/go-web/references/convert-to-go-project.md"
CONVERSION_COMMAND_WORKFLOW_ROUTE='Read `${CLAUDE_PLUGIN_ROOT}/references/convert-to-go-project.md`'
CONVERSION_SKILL_WORKFLOW_ROUTE='Read `<PLUGIN_ROOT>/references/convert-to-go-project.md`'
CREATE_COMMAND="$ROOT_DIR/plugins/go-web/commands/create-go-project.md"
CREATE_SKILL="$ROOT_DIR/plugins/go-web/skills/create-go-project/SKILL.md"
CREATE_WORKFLOW="$ROOT_DIR/plugins/go-web/references/create-go-project.md"
CREATE_COMMAND_WORKFLOW_ROUTE='Read `${CLAUDE_PLUGIN_ROOT}/references/create-go-project.md`'
CREATE_SKILL_WORKFLOW_ROUTE='Read `<PLUGIN_ROOT>/references/create-go-project.md`'
CREATE_NESTED_REFERENCES=(
  "$ROOT_DIR/plugins/go-web/references/clerk-integration.md"
  "$ROOT_DIR/plugins/go-web/references/deployment/nixpacks.md"
  "$ROOT_DIR/plugins/go-web/references/deployment/dockerfile.md"
)
FIXTURE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-go-web-XXXXXX")
ERRORS=0

fail() {
  echo "FAIL: $1"
  ERRORS=$((ERRORS + 1))
}

require_literal() {
  local file="$1"
  local text="$2"
  local label="$3"

  case "$(<"$file")" in
    *"$text"*) ;;
    *) fail "$label" ;;
  esac
}

reject_literal() {
  local file="$1"
  local text="$2"
  local label="$3"

  case "$(<"$file")" in
    *"$text"*) fail "$label" ;;
    *) ;;
  esac
}

require_before() {
  local file="$1"
  local first="$2"
  local second="$3"
  local label="$4"
  local first_line
  local second_line

  first_line=$(awk -v text="$first" 'index($0, text) { print NR; exit }' "$file")
  second_line=$(awk -v text="$second" 'index($0, text) { print NR; exit }' "$file")
  if [ -z "$first_line" ] || [ -z "$second_line" ] || [ "$first_line" -ge "$second_line" ]; then
    fail "$label"
  fi
}

write_fixture_support() {
  local fixture="$1"

  mkdir -p "$fixture/internal/config" "$fixture/internal/database" "$fixture/internal/testutil"
  cat > "$fixture/go.mod" <<'EOF'
module example.com/fixture

go 1.23
EOF
  cat > "$fixture/internal/config/config.go" <<'EOF'
package config

type SiteConfig struct {
	Name string
	URL  string
}

type Config struct {
	DatabaseURL string
	Port        string
	Env         string
	Site        SiteConfig
}
EOF
  cat > "$fixture/internal/database/database.go" <<'EOF'
package database

import "context"

type DB struct {
	URL string
}

func New(_ context.Context, databaseURL string) (*DB, error) {
	return &DB{URL: databaseURL}, nil
}

func (db *DB) Close() error { return nil }
EOF
}

write_mysql_stub() {
  local fixture="$1"

  mkdir -p "$fixture/stubs/mysql"
  cat >> "$fixture/go.mod" <<'EOF'

require github.com/go-sql-driver/mysql v0.0.0

replace github.com/go-sql-driver/mysql => ./stubs/mysql
EOF
  cat > "$fixture/stubs/mysql/go.mod" <<'EOF'
module github.com/go-sql-driver/mysql

go 1.23
EOF
  cat > "$fixture/stubs/mysql/mysql.go" <<'EOF'
package mysql

type Config struct {
	DBName string
}

func ParseDSN(string) (*Config, error) {
	return &Config{DBName: "test"}, nil
}

func (c *Config) FormatDSN() string {
	return c.DBName
}
EOF
}

write_fixture_test() {
  local fixture="$1"
  local backend="$2"

  if [ "$backend" = "sqlite" ]; then
    cat > "$fixture/internal/testutil/testutil_test.go" <<'EOF'
package testutil

import (
	"path/filepath"
	"testing"
)

func TestSQLiteHelpersUseIsolatedFiles(t *testing.T) {
	db := NewTestDB(t)
	cfg := NewTestConfig(t)

	if db.URL == ":memory:" || cfg.DatabaseURL == ":memory:" {
		t.Fatal("SQLite helpers must not use pooled in-memory databases")
	}
	if db.URL == cfg.DatabaseURL {
		t.Fatal("SQLite helpers must allocate isolated database files")
	}
	if filepath.Base(db.URL) != "test.db" || filepath.Base(cfg.DatabaseURL) != "test.db" {
		t.Fatalf("unexpected SQLite test database paths: %q and %q", db.URL, cfg.DatabaseURL)
	}
}
EOF
    return
  fi

  cat > "$fixture/internal/testutil/testutil_test.go" <<'EOF'
package testutil

import "testing"

func TestNewTestDBRequiresTestDatabaseURL(t *testing.T) {
	t.Setenv("TEST_DATABASE_URL", "")
	NewTestDB(t)
	t.Fatal("NewTestDB must skip without TEST_DATABASE_URL")
}

func TestNewTestConfigRequiresTestDatabaseURL(t *testing.T) {
	t.Setenv("TEST_DATABASE_URL", "")
	NewTestConfig(t)
	t.Fatal("NewTestConfig must skip without TEST_DATABASE_URL")
}
EOF
}

render_and_verify_fixture() {
  local backend="$1"
  local fixture="$FIXTURE_ROOT/$backend"
  local output

  write_fixture_support "$fixture"
  if [ "$backend" = "mysql" ]; then
    write_mysql_stub "$fixture"
  fi
  sed 's|{{PROJECT_NAME}}|example.com/fixture|g' \
    "$TEMPLATE_DIR/app/testutil.$backend.go" > "$fixture/internal/testutil/testutil.go"
  write_fixture_test "$fixture" "$backend"

  gofmt -w \
    "$fixture/internal/config/config.go" \
    "$fixture/internal/database/database.go" \
    "$fixture/internal/testutil/testutil.go" \
    "$fixture/internal/testutil/testutil_test.go"
  if [ -n "$(gofmt -l "$fixture/internal")" ]; then
    fail "$backend fixture contains unformatted Go files"
    return
  fi

  if ! (cd "$fixture" && go generate ./... && go build ./...); then
    fail "$backend fixture generation or build failed"
    return
  fi

  if ! output=$(cd "$fixture" && /bin/bash "$ROOT_DIR/scripts/run-go-tests.sh" -v ./... 2>&1); then
    printf '%s\n' "$output"
    fail "$backend fixture tests failed"
    return
  fi

  if [[ "$output" == *"Managed Darwin worker compiled Go tests"* ]]; then
    return
  fi

  if [ "$backend" != "sqlite" ]; then
    case "$output" in
      *"TEST_DATABASE_URL is required"*) ;;
      *) fail "$backend helper did not report its missing test prerequisite" ;;
    esac
  fi
}

render_and_verify_create_project_fixture() {
  local fixture="$FIXTURE_ROOT/create-project"
  local source
  local target
  local required_path

  while IFS='|' read -r source target; do
    mkdir -p "$fixture/$(dirname "$target")"
    sed \
      -e 's|{{PROJECT_NAME}}|example-app|g' \
      -e 's|{{DATABASE_TYPE}}|sqlite3|g' \
      "$TEMPLATE_DIR/$source" > "$fixture/$target"
  done <<'EOF'
core/go.mod|go.mod
core/gitignore|.gitignore
core/package.json|package.json
core/Makefile|Makefile
core/air.toml|.air.toml
core/golangci.yml|.golangci.yml
env/envrc.example|.envrc.example
env/envrc.sqlite|.envrc
db/sqlc.sqlite.yaml|sqlc/sqlc.yaml
db/queries-example.sql|sqlc/queries/example.sql
db/migration-initial.sqlite.sql|internal/database/migrations/001_initial.sql
db/database.sqlite.go|internal/database/database.go
app/main.go|cmd/server/main.go
app/server.go|cmd/server/server.go
app/main_test.go|cmd/server/main_test.go
app/slog.go|cmd/server/slog.go
app/generate.go|cmd/server/generate.go
app/config.go|internal/config/config.go
app/ctxkeys.go|internal/ctxkeys/keys.go
app/meta.go|internal/meta/meta.go
app/meta-context.go|internal/meta/context.go
app/middleware.go|internal/middleware/middleware.go
app/handler.go|internal/handler/handler.go
app/home.go|internal/handler/home.go
app/testutil.sqlite.go|internal/testutil/testutil.go
templ/meta.templ|templates/layouts/meta.templ
templ/base.templ|templates/layouts/base.templ
templ/home.templ|templates/pages/home.templ
css/input.css|static/css/input.css
ci/ci.yml|.github/workflows/ci.yml
ci/dependabot.yml|.github/dependabot.yml
EOF

  mkdir -p "$fixture/static/js" "$fixture/data"
  touch "$fixture/static/js/.gitkeep" "$fixture/data/.gitkeep"

  for required_path in \
    go.mod \
    Makefile \
    cmd/server/main.go \
    internal/database/database.go \
    internal/database/migrations/001_initial.sql \
    internal/testutil/testutil.go \
    templates/layouts/base.templ \
    templates/pages/home.templ \
    static/css/input.css \
    static/js/.gitkeep \
    data/.gitkeep \
    .github/workflows/ci.yml; do
    if [ ! -f "$fixture/$required_path" ]; then
      fail "create-go-project fixture is missing $required_path"
    fi
  done

  if rg -n '\{\{(PROJECT_NAME|DATABASE_TYPE)\}\}' "$fixture"; then
    fail "create-go-project fixture contains unresolved placeholders"
  fi
  require_literal "$fixture/go.mod" "module example-app" \
    "create-go-project fixture must substitute the project name"
  require_literal "$fixture/Makefile" 'goose -dir $(MIGRATIONS_DIR) sqlite3' \
    "create-go-project fixture must substitute the database type"
  require_literal "$fixture/.envrc" 'export DATABASE_URL="./data/example-app.db"' \
    "create-go-project fixture must select the SQLite environment"
}

echo "=== go-web Database Test Helper Fixtures ==="

for backend in sqlite postgres mysql; do
  template="$TEMPLATE_DIR/app/testutil.$backend.go"
  if [ ! -f "$template" ]; then
    fail "missing $backend test helper template"
    continue
  fi
  require_literal "$template" "t.Helper()" "$backend helper must mark helper frames"
  require_literal "$template" "t.Cleanup(" "$backend helper must own cleanup"
done

if [ -f "$TEMPLATE_DIR/app/testutil.sqlite.go" ]; then
  require_literal "$TEMPLATE_DIR/app/testutil.sqlite.go" "t.TempDir()" \
    "SQLite helper must allocate an isolated temporary directory"
  reject_literal "$TEMPLATE_DIR/app/testutil.sqlite.go" '":memory:"' \
    "SQLite helper must not use a pooled in-memory database"
fi

for backend in postgres mysql; do
  template="$TEMPLATE_DIR/app/testutil.$backend.go"
  if [ -f "$template" ]; then
    require_literal "$template" 'os.Getenv("TEST_DATABASE_URL")' \
      "$backend helper must use explicit test-only configuration"
    reject_literal "$template" 'os.Getenv("DATABASE_URL")' \
      "$backend helper must not fall back to application configuration"
  fi
done

require_literal "$TEMPLATE_DIR/env/envrc.postgres" 'export TEST_DATABASE_URL=' \
  "PostgreSQL environment template must name test-only configuration"
require_literal "$TEMPLATE_DIR/env/envrc.mysql" 'export TEST_DATABASE_URL=' \
  "MySQL environment template must name test-only configuration"
require_literal "$TEMPLATE_DIR/ci/ci.yml" 'TEST_DATABASE_URL: "postgresql://test:test@localhost:5432/testdb?sslmode=disable"' \
  "PostgreSQL CI fixture must run database tests with test-only configuration"
require_literal "$TEMPLATE_DIR/ci/ci.yml" 'TEST_DATABASE_URL: "root:test@tcp(localhost:3306)/testdb"' \
  "MySQL CI fixture must run database tests with test-only configuration"

if [ ! -f "$CREATE_WORKFLOW" ]; then
  fail "missing shared create-go-project workflow"
else
  require_literal "$CREATE_WORKFLOW" '`<PLUGIN_ROOT>/templates/`' \
    "shared creation workflow must use the plugin template library"
  require_literal "$CREATE_WORKFLOW" '`<PLUGIN_ROOT>/templates/README.md`' \
    "shared creation workflow must use the plugin template manifest"
  reject_literal "$CREATE_WORKFLOW" '${CLAUDE_PLUGIN_ROOT}' \
    "shared creation workflow must not depend on a Claude-only plugin root"
  require_literal "$CREATE_WORKFLOW" "app/testutil.<db>.go" \
    "shared creation workflow must select the database-specific test helper"
  reject_literal "$CREATE_WORKFLOW" "app/testutil.go" \
    "shared creation workflow must not select the generic SQLite helper"
  require_literal "$CREATE_WORKFLOW" "Ask the user which database they want to use" \
    "shared creation workflow must preserve database confirmation"
  require_literal "$CREATE_WORKFLOW" 'create the project at `./$SKILL_ARGS/`' \
    "shared creation workflow must define the generated project location"
  require_literal "$CREATE_WORKFLOW" 'If `./$SKILL_ARGS` already exists, stop before creating or modifying any files' \
    "shared creation workflow must reject an existing project target"
  require_before "$CREATE_WORKFLOW" \
    '## Security Validation' \
    '## Persistent Loop Protocol' \
    "shared creation workflow must validate the target before initializing loop state"
  require_literal "$CREATE_WORKFLOW" '`SKILL_ARGS` must already contain the project name' \
    "shared creation workflow must require a portable argument binding"
  reject_literal "$CREATE_WORKFLOW" '$ARGUMENTS' \
    "shared creation workflow must not consume a surface-specific argument token"
  require_literal "$CREATE_WORKFLOW" "go build -o" \
    "shared creation workflow must verify the generated project build"
  require_before "$CREATE_WORKFLOW" \
    'Replace `internal/database/migrations/001_initial.sql` with the actual domain table(s) and indexes' \
    '"./tmp/$SKILL_ARGS" &' \
    "shared creation workflow must replace the domain migration before starting the server"
  require_literal "$CREATE_WORKFLOW" "On Codex, skip loop initialization" \
    "shared creation workflow must not initialize Claude loop state on Codex"
  require_literal "$CREATE_WORKFLOW" "On Codex, do not emit a completion marker" \
    "shared creation workflow must not emit Claude completion markers on Codex"
fi

for nested_reference in "${CREATE_NESTED_REFERENCES[@]}"; do
  require_literal "$nested_reference" '<PLUGIN_ROOT>' \
    "shared creation reference must use the portable plugin root: $nested_reference"
  require_literal "$nested_reference" 'If the caller has not bound it, resolve it directly' \
    "shared creation reference must support callers without a bound plugin root: $nested_reference"
  require_literal "$nested_reference" 'ascend two directories' \
    "shared creation reference must resolve the plugin root from a Codex skill: $nested_reference"
  reject_literal "$nested_reference" '${CLAUDE_PLUGIN_ROOT}' \
    "shared creation reference must not depend on a Claude-only plugin root: $nested_reference"
done

require_literal "$CREATE_COMMAND" "$CREATE_COMMAND_WORKFLOW_ROUTE" \
  "create-go-project command must route to the shared creation workflow"
require_literal "$CREATE_COMMAND" 'Bind the injected `$ARGUMENTS` value to `SKILL_ARGS`' \
  "create-go-project command must bind Claude arguments to the portable contract"

if [ ! -f "$CREATE_SKILL" ]; then
  fail "missing create-go-project Codex skill"
else
  require_literal "$CREATE_SKILL" "ascend two directories" \
    "create-go-project skill must resolve its concrete plugin root on Codex"
  require_literal "$CREATE_SKILL" 'Bind the project name to `SKILL_ARGS`' \
    "create-go-project skill must bind Codex arguments to the portable contract"
  require_literal "$CREATE_SKILL" "$CREATE_SKILL_WORKFLOW_ROUTE" \
    "create-go-project skill must route to the shared creation workflow"
fi

if [ ! -f "$CONVERSION_WORKFLOW" ]; then
  fail "missing shared convert-to-go-project workflow"
else
  require_literal "$CONVERSION_WORKFLOW" \
    '| Express.js / Fastify / other Node HTTP | `<PLUGIN_ROOT>/references/migrations/express.md` |' \
    "shared conversion workflow must route Node HTTP frameworks to the Express migration guide"
  require_literal "$CONVERSION_WORKFLOW" \
    '| Django / Flask / FastAPI | `<PLUGIN_ROOT>/references/migrations/django-flask.md` |' \
    "shared conversion workflow must route Python frameworks to the Django and Flask migration guide"
  require_literal "$CONVERSION_WORKFLOW" \
    '| Laravel / other PHP | `<PLUGIN_ROOT>/references/migrations/laravel.md` |' \
    "shared conversion workflow must route PHP frameworks to the Laravel migration guide"
  require_literal "$CONVERSION_WORKFLOW" \
    '| Next.js / React SPA | `<PLUGIN_ROOT>/references/migrations/nextjs.md` |' \
    "shared conversion workflow must route React frameworks to the Next.js migration guide"
  require_literal "$CONVERSION_WORKFLOW" \
    '| `go.mod` | Go (existing) | Already Go - extend rather than convert |' \
    "shared conversion workflow must extend existing Go projects rather than replace them"
  require_literal "$CONVERSION_WORKFLOW" \
    '`<PLUGIN_ROOT>/references/migrations/client-side-templui.md`' \
    "shared conversion workflow must route client-side interactivity to the templUI migration guide"
  require_literal "$CONVERSION_WORKFLOW" '`<PLUGIN_ROOT>/templates/`' \
    "shared conversion workflow must use the plugin template library"
  require_literal "$CONVERSION_WORKFLOW" '`<PLUGIN_ROOT>/templates/README.md`' \
    "shared conversion workflow must use the plugin template manifest"
  reject_literal "$CONVERSION_WORKFLOW" '${CLAUDE_PLUGIN_ROOT}' \
    "shared conversion workflow must not depend on a Claude-only plugin root"
  require_literal "$CONVERSION_WORKFLOW" 'On Codex, skip loop initialization' \
    "shared conversion workflow must not initialize Claude loop state on Codex"
  require_literal "$CONVERSION_WORKFLOW" 'On Codex, do not emit a completion marker' \
    "shared conversion workflow must not emit Claude completion markers on Codex"
  require_literal "$CONVERSION_WORKFLOW" "app/testutil.<db>.go" \
    "shared conversion workflow must select the database-specific test helper"
  reject_literal "$CONVERSION_WORKFLOW" "app/testutil.go" \
    "shared conversion workflow must not select the generic SQLite helper"
fi

require_literal "$CONVERSION_COMMAND" "$CONVERSION_COMMAND_WORKFLOW_ROUTE" \
  "convert-to-go-project command must route to the shared conversion workflow"
require_literal "$CONVERSION_COMMAND" 'Bind the injected `$ARGUMENTS` value to `SKILL_ARGS`' \
  "convert-to-go-project command must bind Claude arguments to the portable contract"
require_literal "$CONVERSION_COMMAND" 'Bind `<PLUGIN_ROOT>` in the shared workflow to `${CLAUDE_PLUGIN_ROOT}`' \
  "convert-to-go-project command must bind the portable plugin root on Claude"

if [ ! -f "$CONVERSION_SKILL" ]; then
  fail "missing convert-to-go-project Codex skill"
else
  require_literal "$CONVERSION_SKILL" 'ascend two directories' \
    "convert-to-go-project skill must resolve its concrete plugin root on Codex"
  require_literal "$CONVERSION_SKILL" 'Bind the optional target directory to `SKILL_ARGS`' \
    "convert-to-go-project skill must bind Codex arguments to the portable contract"
  require_literal "$CONVERSION_SKILL" "$CONVERSION_SKILL_WORKFLOW_ROUTE" \
    "convert-to-go-project skill must route to the shared conversion workflow"
fi

require_literal "$TEMPLATE_DIR/README.md" "app/testutil.<db>.go" \
  "template manifest must document database-specific test helpers"
reject_literal "$TEMPLATE_DIR/README.md" "app/testutil.go" \
  "template manifest must not document the generic SQLite helper"

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS go-web template issue(s)"
  exit 1
fi

for backend in sqlite postgres mysql; do
  render_and_verify_fixture "$backend"
done
render_and_verify_create_project_fixture

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS go-web fixture issue(s)"
  exit 1
fi

echo "All go-web database test helper fixtures passed."
