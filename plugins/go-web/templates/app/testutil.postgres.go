package testutil

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"net/url"
	"os"
	"strings"
	"testing"

	"{{PROJECT_NAME}}/internal/config"
	"{{PROJECT_NAME}}/internal/database"
)

func NewTestDB(t *testing.T) *database.DB {
	t.Helper()

	databaseURL := newTestDatabaseURL(t)
	db, err := database.New(context.Background(), databaseURL)
	if err != nil {
		t.Fatalf("failed to create test database: %v", err)
	}

	t.Cleanup(func() {
		if err := db.Close(); err != nil {
			t.Errorf("failed to close test database: %v", err)
		}
	})

	return db
}

func NewTestConfig(t *testing.T) *config.Config {
	t.Helper()

	return &config.Config{
		DatabaseURL: newTestDatabaseURL(t),
		Port:        "0",
		Env:         "test",
		Site: config.SiteConfig{
			Name: "{{PROJECT_NAME}}",
			URL:  "http://localhost:3000",
		},
	}
}

func newTestDatabaseURL(t *testing.T) string {
	t.Helper()

	baseURL := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if baseURL == "" {
		t.Skip("TEST_DATABASE_URL is required for PostgreSQL tests")
	}

	parsedURL, err := url.Parse(baseURL)
	if err != nil {
		t.Fatalf("invalid TEST_DATABASE_URL: %v", err)
	}
	if parsedURL.Scheme != "postgres" && parsedURL.Scheme != "postgresql" {
		t.Fatalf("TEST_DATABASE_URL must use the postgres or postgresql scheme")
	}
	databaseName := strings.Trim(parsedURL.Path, "/")
	if databaseName == "" || !strings.Contains(strings.ToLower(databaseName), "test") {
		t.Fatalf("TEST_DATABASE_URL must name a test database")
	}

	ctx := context.Background()
	admin, err := sql.Open("pgx", baseURL)
	if err != nil {
		t.Fatalf("failed to open PostgreSQL test database: %v", err)
	}
	if err := admin.PingContext(ctx); err != nil {
		if closeErr := admin.Close(); closeErr != nil {
			t.Errorf("failed to close PostgreSQL test database: %v", closeErr)
		}
		t.Fatalf("failed to connect to PostgreSQL test database: %v", err)
	}

	schema := "test_" + randomIdentifier(t)
	if _, err := admin.ExecContext(ctx, "CREATE SCHEMA "+schema); err != nil {
		if closeErr := admin.Close(); closeErr != nil {
			t.Errorf("failed to close PostgreSQL test database: %v", closeErr)
		}
		t.Fatalf("failed to create PostgreSQL test schema: %v", err)
	}

	t.Cleanup(func() {
		if _, err := admin.ExecContext(context.Background(), "DROP SCHEMA IF EXISTS "+schema+" CASCADE"); err != nil {
			t.Errorf("failed to drop PostgreSQL test schema: %v", err)
		}
		if err := admin.Close(); err != nil {
			t.Errorf("failed to close PostgreSQL test database: %v", err)
		}
	})

	query := parsedURL.Query()
	query.Set("search_path", schema)
	parsedURL.RawQuery = query.Encode()

	return parsedURL.String()
}

func randomIdentifier(t *testing.T) string {
	t.Helper()

	value := make([]byte, 8)
	if _, err := rand.Read(value); err != nil {
		t.Fatalf("failed to create test database identifier: %v", err)
	}

	return hex.EncodeToString(value)
}
