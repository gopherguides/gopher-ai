package handler

import (
    "{{PROJECT_NAME}}/internal/config"
    "{{PROJECT_NAME}}/internal/database"

    "github.com/labstack/echo/v4"
)

type Handler struct {
    cfg *config.Config
    db  *database.DB
}

func New(cfg *config.Config, db *database.DB) *Handler {
    return &Handler{
        cfg: cfg,
        db:  db,
    }
}

func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // Static files
    e.Static("/static", "static")
    // If using templUI (admin dashboard), uncomment:
    // e.Static("/assets", "assets")

    // Health check
    e.GET("/health", h.Health)

    // Public routes
    e.GET("/", h.Home)

    // Admin routes (if dashboard selected)
    // admin := e.Group("/admin")
    // admin.GET("", h.AdminDashboard)
}
