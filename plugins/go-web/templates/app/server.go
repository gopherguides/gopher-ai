package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const (
	readHeaderTimeout = 5 * time.Second
	readTimeout       = 15 * time.Second
	writeTimeout      = 30 * time.Second
	idleTimeout       = 60 * time.Second
	shutdownTimeout   = 10 * time.Second
)

type server interface {
	Start(string) error
	Shutdown(context.Context) error
	Close() error
}

func configureHTTPServer(srv *http.Server) {
	srv.ReadHeaderTimeout = readHeaderTimeout
	srv.ReadTimeout = readTimeout
	srv.WriteTimeout = writeTimeout
	srv.IdleTimeout = idleTimeout
}

func serve(ctx context.Context, srv server, timeout time.Duration) error {
	serveErr := make(chan error, 1)
	go func() {
		serveErr <- srv.Start("")
	}()

	select {
	case err := <-serveErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		if err == nil {
			return errors.New("serve stopped unexpectedly")
		}
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	shutdownErr := srv.Shutdown(shutdownCtx)
	if shutdownErr != nil {
		shutdownErr = fmt.Errorf("shutdown: %w", shutdownErr)
		if err := srv.Close(); err != nil {
			shutdownErr = errors.Join(shutdownErr, fmt.Errorf("close: %w", err))
		}
	}

	err := <-serveErr
	if err != nil && !errors.Is(err, http.ErrServerClosed) {
		err = fmt.Errorf("serve: %w", err)
	} else {
		err = nil
	}
	return errors.Join(shutdownErr, err)
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
			if !errors.Is(err, syscall.EADDRINUSE) {
				return nil, "", fmt.Errorf("failed to listen on port %d: %w", port, err)
			}
			continue
		}
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
