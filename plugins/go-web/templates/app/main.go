package main

import (
    "context"
    "errors"
    "fmt"
    "log/slog"
    "net"
    "os"
    "os/signal"
    "strconv"
    "strings"
    "syscall"
    "time"

    "{{PROJECT_NAME}}/internal/config"
    "{{PROJECT_NAME}}/internal/database"
    "{{PROJECT_NAME}}/internal/handler"
    "{{PROJECT_NAME}}/internal/middleware"

    chimw "github.com/go-chi/chi/v5/middleware"
    "github.com/labstack/echo/v4"
)

func main() {
    cfg := config.Load()

    ctx := context.Background()
    db, err := database.New(ctx, cfg.DatabaseURL)
    if err != nil {
        slog.Error("failed to connect to database", "error", err)
        os.Exit(1)
    }
    defer db.Close()

    e := echo.New()
    e.HideBanner = true
    e.HidePort = true

    ln, actualPort, err := findAvailablePort(cfg.Port)
    if err != nil {
        slog.Error("failed to find available port", "error", err)
        os.Exit(1)
    }
    e.Listener = ln

    if actualPort != cfg.Port {
        slog.Warn("configured port unavailable, using next available", "configured", cfg.Port, "actual", actualPort)
        cfg.Port = actualPort
        cfg.Site.URL = replacePort(cfg.Site.URL, actualPort)
    }

    middleware.Setup(e, cfg)

    h := handler.New(cfg, db)
    h.RegisterRoutes(e)

    e.Use(echo.WrapMiddleware(chimw.Logger))

    go func() {
        slog.Info("starting server", "url", fmt.Sprintf("http://localhost:%s", cfg.Port), "env", cfg.Env)
        if err := e.Start(""); err != nil {
            slog.Info("shutting down server")
        }
    }()

    quit := make(chan os.Signal, 1)
    signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
    <-quit

    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    if err := e.Shutdown(ctx); err != nil {
        slog.Error("server shutdown error", "error", err)
    }

    slog.Info("server stopped")
}

func findAvailablePort(configuredPort string) (net.Listener, string, error) {
    startPort, err := strconv.Atoi(configuredPort)
    if err != nil {
        return nil, "", fmt.Errorf("invalid port %q: %w", configuredPort, err)
    }

    maxPort := startPort + 100
    for port := startPort; port <= maxPort; port++ {
        addr := ":" + strconv.Itoa(port)
        ln, err := net.Listen("tcp", addr)
        if err != nil {
            // Only retry for "address in use" errors; return other errors immediately
            if !errors.Is(err, syscall.EADDRINUSE) {
                return nil, "", fmt.Errorf("failed to listen on port %d: %w", port, err)
            }
            continue
        }
        // Get actual bound port (important when port is 0)
        actualPort := ln.Addr().(*net.TCPAddr).Port
        return ln, strconv.Itoa(actualPort), nil
    }

    return nil, "", fmt.Errorf("no available port found in range %d-%d", startPort, maxPort)
}

func replacePort(rawURL string, newPort string) string {
    const localhostPrefix = "://localhost:"
    if idx := strings.Index(rawURL, localhostPrefix); idx >= 0 {
        afterScheme := idx + len(localhostPrefix)
        end := strings.IndexAny(rawURL[afterScheme:], "/?#")
        if end == -1 {
            return rawURL[:afterScheme] + newPort
        }
        return rawURL[:afterScheme] + newPort + rawURL[afterScheme+end:]
    }
    return rawURL
}
