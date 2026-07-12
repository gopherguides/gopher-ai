package database

import (
    "context"
    "embed"
    "errors"
    "fmt"
    "io/fs"

    "github.com/jackc/pgx/v5/pgxpool"
    "github.com/jackc/pgx/v5/stdlib"
    "github.com/pressly/goose/v3"
    "{{PROJECT_NAME}}/internal/database/sqlc"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

type DB struct {
    Pool    *pgxpool.Pool
    Queries *sqlc.Queries
}

func New(ctx context.Context, databaseURL string) (_ *DB, err error) {
    pool, err := pgxpool.New(ctx, databaseURL)
    if err != nil {
        return nil, fmt.Errorf("unable to create connection pool: %w", err)
    }
    defer func() {
        if err != nil {
            pool.Close()
        }
    }()

    if err := pool.Ping(ctx); err != nil {
        return nil, fmt.Errorf("unable to ping database: %w", err)
    }

    db := &DB{
        Pool:    pool,
        Queries: sqlc.New(pool),
    }

    if err := db.migrate(ctx); err != nil {
        return nil, fmt.Errorf("unable to run migrations: %w", err)
    }

    return db, nil
}

func (db *DB) Close() error {
    db.Pool.Close()
    return nil
}

func (db *DB) migrate(ctx context.Context) (err error) {
    migrations, err := fs.Sub(migrationsFS, "migrations")
    if err != nil {
        return fmt.Errorf("failed to load migrations: %w", err)
    }

    conn := stdlib.OpenDBFromPool(db.Pool)
    defer func() {
        if closeErr := conn.Close(); closeErr != nil {
            err = errors.Join(err, fmt.Errorf("failed to close migration connection: %w", closeErr))
        }
    }()

    provider, err := goose.NewProvider(
        goose.DialectPostgres,
        conn,
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
