package main

import (
    "log/slog"
    "os"
    "strings"
    "time"

    "github.com/lmittmann/tint"
)

func init() {
    level := getLogLevel()
    isDev := strings.ToLower(os.Getenv("ENV")) == "development"

    var handler slog.Handler
    if isDev {
        handler = tint.NewHandler(os.Stderr, &tint.Options{
            Level:      level,
            TimeFormat: time.Kitchen,
            AddSource:  level == slog.LevelDebug,
        })
    } else {
        handler = slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
            Level:     level,
            AddSource: false,
        })
    }

    slog.SetDefault(slog.New(handler))
}

func getLogLevel() slog.Level {
    switch strings.ToUpper(os.Getenv("LOG_LEVEL")) {
    case "DEBUG":
        return slog.LevelDebug
    case "WARN":
        return slog.LevelWarn
    case "ERROR":
        return slog.LevelError
    default:
        return slog.LevelInfo
    }
}
