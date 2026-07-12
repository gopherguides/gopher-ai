package database

import (
    "context"
    "database/sql"
    "embed"
    "errors"
    "fmt"
    "io/fs"
    "os"
    "path/filepath"

    "github.com/pressly/goose/v3"
    _ "modernc.org/sqlite"
    "{{PROJECT_NAME}}/internal/database/sqlc"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

type DB struct {
    Conn    *sql.DB
    Queries *sqlc.Queries
}

func New(ctx context.Context, databasePath string) (_ *DB, err error) {
    dir := filepath.Dir(databasePath)
    if err := os.MkdirAll(dir, 0755); err != nil {
        return nil, fmt.Errorf("unable to create database directory: %w", err)
    }

    conn, err := sql.Open("sqlite", databasePath+"?_foreign_keys=on&_journal_mode=WAL")
    if err != nil {
        return nil, fmt.Errorf("unable to open database: %w", err)
    }
    defer func() {
        if err != nil {
            if closeErr := conn.Close(); closeErr != nil {
                err = errors.Join(err, fmt.Errorf("failed to close database: %w", closeErr))
            }
        }
    }()

    if err := conn.PingContext(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    db := &DB{
        Conn:    conn,
        Queries: sqlc.New(conn),
    }

    if err := db.migrate(ctx); err != nil {
        return nil, fmt.Errorf("unable to run migrations: %w", err)
    }

    return db, nil
}

func (db *DB) Close() error {
    return db.Conn.Close()
}

func (db *DB) migrate(ctx context.Context) error {
    migrations, err := fs.Sub(migrationsFS, "migrations")
    if err != nil {
        return fmt.Errorf("failed to load migrations: %w", err)
    }

    provider, err := goose.NewProvider(
        goose.DialectSQLite3,
        db.Conn,
        migrations,
        goose.WithDisableGlobalRegistry(true),
    )
    if err != nil {
        return fmt.Errorf("failed to create goose provider: %w", err)
    }

    if _, err := provider.Up(ctx); err != nil {
        return fmt.Errorf("failed to run migrations: %w", err)
    }

    return nil
}
