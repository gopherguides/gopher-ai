package testutil

import (
	"context"
	"path/filepath"
	"testing"

	"{{PROJECT_NAME}}/internal/config"
	"{{PROJECT_NAME}}/internal/database"
)

func NewTestDB(t *testing.T) *database.DB {
	t.Helper()

	databaseURL := filepath.Join(t.TempDir(), "test.db")
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
		DatabaseURL: filepath.Join(t.TempDir(), "test.db"),
		Port:        "0",
		Env:         "test",
		Site: config.SiteConfig{
			Name: "{{PROJECT_NAME}}",
			URL:  "http://localhost:3000",
		},
	}
}
