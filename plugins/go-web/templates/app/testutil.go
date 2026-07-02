package testutil

import (
    "context"
    "testing"

    "{{PROJECT_NAME}}/internal/config"
    "{{PROJECT_NAME}}/internal/database"
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
            Name: "{{PROJECT_NAME}}",
            URL:  "http://localhost:3000",
        },
    }
}
