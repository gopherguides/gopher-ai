package testutil

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"os"
	"strings"
	"testing"

	"github.com/go-sql-driver/mysql"
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
		t.Skip("TEST_DATABASE_URL is required for MySQL tests")
	}

	baseConfig, err := mysql.ParseDSN(baseURL)
	if err != nil {
		t.Fatalf("invalid TEST_DATABASE_URL: %v", err)
	}
	if baseConfig.DBName == "" || !strings.Contains(strings.ToLower(baseConfig.DBName), "test") {
		t.Fatalf("TEST_DATABASE_URL must name a test database")
	}

	adminConfig := *baseConfig
	adminConfig.DBName = ""
	admin, err := sql.Open("mysql", adminConfig.FormatDSN())
	if err != nil {
		t.Fatalf("failed to open MySQL test database: %v", err)
	}
	if err := admin.PingContext(context.Background()); err != nil {
		if closeErr := admin.Close(); closeErr != nil {
			t.Errorf("failed to close MySQL test database: %v", closeErr)
		}
		t.Fatalf("failed to connect to MySQL test database: %v", err)
	}

	databaseName := "test_" + randomIdentifier(t)
	if _, err := admin.ExecContext(context.Background(), "CREATE DATABASE "+databaseName); err != nil {
		if closeErr := admin.Close(); closeErr != nil {
			t.Errorf("failed to close MySQL test database: %v", closeErr)
		}
		t.Fatalf("failed to create MySQL test database: %v", err)
	}

	t.Cleanup(func() {
		if _, err := admin.ExecContext(context.Background(), "DROP DATABASE IF EXISTS "+databaseName); err != nil {
			t.Errorf("failed to drop MySQL test database: %v", err)
		}
		if err := admin.Close(); err != nil {
			t.Errorf("failed to close MySQL test database: %v", err)
		}
	})

	testConfig := *baseConfig
	testConfig.DBName = databaseName

	return testConfig.FormatDSN()
}

func randomIdentifier(t *testing.T) string {
	t.Helper()

	value := make([]byte, 8)
	if _, err := rand.Read(value); err != nil {
		t.Fatalf("failed to create test database identifier: %v", err)
	}

	return hex.EncodeToString(value)
}
