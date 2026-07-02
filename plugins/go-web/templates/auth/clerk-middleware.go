import (
    "github.com/clerk/clerk-sdk-go/v2"
    "github.com/clerk/clerk-sdk-go/v2/jwt"
)

// ClerkAuth verifies Clerk session tokens and sets user info in context.
// Pass cfg.ClerkSecretKey when creating the middleware.
func ClerkAuth(clerkSecretKey string) echo.MiddlewareFunc {
    // Configure Clerk SDK with the secret key for JWT verification
    clerk.SetKey(clerkSecretKey)

    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            sessionToken := ""

            // Check cookie first (browser sessions)
            if cookie, err := c.Cookie("__session"); err == nil && cookie.Value != "" {
                sessionToken = cookie.Value
            }

            // Fall back to Authorization header (API clients)
            if sessionToken == "" {
                authHeader := c.Request().Header.Get("Authorization")
                if len(authHeader) > 7 && authHeader[:7] == "Bearer " {
                    sessionToken = authHeader[7:]
                }
            }

            if sessionToken == "" {
                c.Set("clerk_user_id", "")
                return next(c)
            }

            // Verify the JWT with Clerk
            claims, err := jwt.Verify(c.Request().Context(), &jwt.VerifyParams{
                Token: sessionToken,
            })
            if err != nil {
                c.Set("clerk_user_id", "")
                return next(c)
            }

            c.Set("clerk_user_id", claims.Subject)
            c.Set("clerk_session_id", claims.SessionID)
            return next(c)
        }
    }
}

// RequireClerkAuth redirects to sign-in if no valid Clerk session exists.
// Must be used AFTER ClerkAuth middleware in the chain.
func RequireClerkAuth() echo.MiddlewareFunc {
    return func(next echo.HandlerFunc) echo.HandlerFunc {
        return func(c echo.Context) error {
            userID := c.Get("clerk_user_id")
            if userID == nil || userID == "" {
                return c.Redirect(302, "/sign-in")
            }
            return next(c)
        }
    }
}
