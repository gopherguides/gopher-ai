#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_DIR="$ROOT_DIR/plugins/go-web/templates"
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

  if ! output=$(cd "$fixture" && go test -v ./... 2>&1); then
    printf '%s\n' "$output"
    fail "$backend fixture tests failed"
    return
  fi

  if [ "$backend" != "sqlite" ]; then
    case "$output" in
      *"TEST_DATABASE_URL is required"*) ;;
      *) fail "$backend helper did not report its missing test prerequisite" ;;
    esac
  fi
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

for command in create-go-project convert-to-go-project; do
  command_file="$ROOT_DIR/plugins/go-web/commands/$command.md"
  require_literal "$command_file" "app/testutil.<db>.go" \
    "$command must select the database-specific test helper"
  reject_literal "$command_file" "app/testutil.go" \
    "$command must not select the generic SQLite helper"
done

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

if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS go-web fixture issue(s)"
  exit 1
fi

echo "All go-web database test helper fixtures passed."
