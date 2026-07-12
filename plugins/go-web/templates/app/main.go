package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"{{PROJECT_NAME}}/internal/config"
	"{{PROJECT_NAME}}/internal/database"
	"{{PROJECT_NAME}}/internal/handler"
	"{{PROJECT_NAME}}/internal/middleware"

	chimw "github.com/go-chi/chi/v5/middleware"
	"github.com/labstack/echo/v4"
)

type echoServer struct {
	e *echo.Echo
}

func (s echoServer) Start(address string) error {
	return s.e.Start(address)
}

func (s echoServer) Shutdown(ctx context.Context) error {
	err := s.e.Shutdown(ctx)
	if errors.Is(err, http.ErrServerClosed) {
		return s.e.Server.Shutdown(ctx)
	}
	return err
}

func (s echoServer) Close() error {
	err := s.e.Close()
	if errors.Is(err, http.ErrServerClosed) {
		return s.e.Server.Close()
	}
	return err
}

var _ server = echoServer{}

func main() {
	if err := run(); err != nil {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg := config.Load()

	ctx := context.Background()
	db, err := database.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("connect to database: %w", err)
	}
	defer func() {
		if err := db.Close(); err != nil {
			slog.Error("failed to close database", "error", err)
		}
	}()

	e := echo.New()
	e.HideBanner = true
	e.HidePort = true

	ln, actualPort, err := findAvailablePort(cfg.Port)
	if err != nil {
		return fmt.Errorf("find available port: %w", err)
	}
	e.Listener = ln
	configureHTTPServer(e.Server)

	if actualPort != cfg.Port {
		slog.Warn("configured port unavailable, using next available", "configured", cfg.Port, "actual", actualPort)
		cfg.Port = actualPort
		cfg.Site.URL = replacePort(cfg.Site.URL, actualPort)
	}

	middleware.Setup(e, cfg)

	h := handler.New(cfg, db)
	h.RegisterRoutes(e)

	e.Use(echo.WrapMiddleware(chimw.Logger))

	signalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	slog.Info("starting server", "url", fmt.Sprintf("http://localhost:%s", cfg.Port), "env", cfg.Env)
	if err := serve(signalCtx, echoServer{e: e}, shutdownTimeout); err != nil {
		return err
	}

	slog.Info("server stopped")
	return nil
}
