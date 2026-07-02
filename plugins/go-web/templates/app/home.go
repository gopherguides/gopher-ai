package handler

import (
    "net/http"

    "{{PROJECT_NAME}}/templates/pages"

    "github.com/labstack/echo/v4"
)

func (h *Handler) Health(c echo.Context) error {
    return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
}

func (h *Handler) Home(c echo.Context) error {
    return pages.Home().Render(c.Request().Context(), c.Response().Writer)
}
