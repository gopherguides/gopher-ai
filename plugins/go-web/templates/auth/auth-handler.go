package handler

import (
    "{{PROJECT_NAME}}/internal/meta"
    "{{PROJECT_NAME}}/templates/pages"

    "github.com/labstack/echo/v4"
)

func (h *Handler) SignIn(c echo.Context) error {
    m := meta.PageMeta{
        Title:       "Sign In",
        Description: "Sign in to your account",
    }
    return pages.SignIn(m, h.cfg.ClerkPublishableKey).Render(c.Request().Context(), c.Response().Writer)
}

func (h *Handler) SignUp(c echo.Context) error {
    m := meta.PageMeta{
        Title:       "Sign Up",
        Description: "Create a new account",
    }
    return pages.SignUp(m, h.cfg.ClerkPublishableKey).Render(c.Request().Context(), c.Response().Writer)
}
