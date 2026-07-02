# Clerk Authentication Integration

Loaded on demand by /go-web:create-go-project and /go-web:convert-to-go-project when the user selects Clerk. Complete file templates live in `${CLAUDE_PLUGIN_ROOT}/templates/auth/` — Read each one, replace `{{PROJECT_NAME}}` with the project module name, and Write it to its target path.

## File Templates to Copy

| Template (`templates/auth/`) | Target in project |
|---|---|
| clerk.templ | templates/components/clerk/clerk.templ |
| sign-in.templ | templates/pages/sign-in.templ |
| sign-up.templ | templates/pages/sign-up.templ |
| auth-handler.go | internal/handler/auth.go |
| clerk-middleware.go | Clerk middleware code — add to internal/middleware/middleware.go (or a new internal/middleware/clerk.go, package middleware, echo import required) |

**CRITICAL Clerk CDN Rules:**
1. The publishable key MUST be a `data-clerk-publishable-key` attribute on the `<script>` tag — NOT in a `<meta>` tag
2. Pin to major version `@clerk/clerk-js@5` — NEVER use `@latest`
3. After loading, `Clerk` is a global object — call `Clerk.load()`, NOT `new Clerk()` or `new window.Clerk()`
4. Always wrap initialization in `window.addEventListener('load', ...)` to ensure the SDK script has executed
5. In templ, use `@templ.Raw()` to render the script tag since templ doesn't support dynamic attributes on `<script>` tags

## Update .envrc and .envrc.example

Add to both files:

```bash
# Clerk (authentication)
export CLERK_PUBLISHABLE_KEY="pk_test_YOUR_KEY_HERE"
export CLERK_SECRET_KEY="sk_test_YOUR_KEY_HERE"
```

## Update internal/config/config.go

Uncomment and populate the Clerk fields:

```go
type Config struct {
    DatabaseURL      string
    Port             string
    Env              string
    Site             SiteConfig
    ClerkPublishableKey string
    ClerkSecretKey      string
}

func Load() *Config {
    cfg := &Config{
        // ... existing fields ...
        ClerkPublishableKey: os.Getenv("CLERK_PUBLISHABLE_KEY"),
        ClerkSecretKey:      os.Getenv("CLERK_SECRET_KEY"),
    }

    if cfg.ClerkPublishableKey == "" {
        slog.Error("CLERK_PUBLISHABLE_KEY environment variable is required")
        os.Exit(1)
    }
    if cfg.ClerkSecretKey == "" {
        slog.Error("CLERK_SECRET_KEY environment variable is required")
        os.Exit(1)
    }

    // ... rest of Load() ...
}
```

## Update internal/middleware/middleware.go
Add Clerk CSP domains and optional auth middleware:

In `Setup()`, update the ContentSecurityPolicy to allow Clerk domains:

```go
ContentSecurityPolicy: "default-src 'self'; script-src 'self' 'unsafe-inline' https://unpkg.com https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline'; connect-src 'self' https://*.clerk.accounts.dev; frame-src 'self' https://*.clerk.accounts.dev; img-src 'self' https://img.clerk.com;",
```

Add Clerk auth middleware for protecting routes. This requires the Clerk SDK:

**Add to go.mod:**
```go
github.com/clerk/clerk-sdk-go/v2 v2.4.1
```

Then add the middleware from `templates/auth/clerk-middleware.go`.

**Usage in handler.go:**

```go
func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // Apply Clerk verification to all routes
    e.Use(middleware.ClerkAuth(h.cfg.ClerkSecretKey))

    // Public routes
    e.GET("/", h.Home)
    e.GET("/sign-in", h.SignIn)
    e.GET("/sign-up", h.SignUp)

    // Protected routes - require valid session
    protected := e.Group("", middleware.RequireClerkAuth())
    protected.GET("/dashboard", h.Dashboard)
}
```

**Note:** `ClerkAuth` verifies the JWT and sets `clerk_user_id` in context (empty string if invalid/missing). `RequireClerkAuth` checks for that value and redirects if empty. This two-middleware pattern allows some routes to optionally use auth info without requiring it.

## Update templates/layouts/base.templ
Add the Clerk script to the `<head>` (it must load before any component scripts):

```templ
import "{{PROJECT_NAME}}/templates/components/clerk"

templ Base(m meta.PageMeta, clerkPublishableKey string) {
    <!DOCTYPE html>
    <html lang="en">
        <head>
            // ... existing meta, CSS, HTMX ...
            @clerk.Script(clerkPublishableKey)
        </head>
        // ... rest of body ...
    </html>
}
```

**Note:** The handler must pass `cfg.ClerkPublishableKey` when rendering any layout that includes Clerk.

**IMPORTANT - Update all existing templates:** When adding Clerk, the Base signature changes from `Base(m meta.PageMeta)` to `Base(m meta.PageMeta, clerkPublishableKey string)`. You MUST update ALL existing templates that call `@layouts.Base(m)` to use the new two-argument signature:
- For pages that need auth (sign-in, sign-up, dashboard): pass the publishable key
- For pages that don't need auth (home, notes, etc.): pass empty string `""`

Example: `@layouts.Base(meta.New("Notes", "..."))` becomes `@layouts.Base(meta.New("Notes", "..."), "")`

## Update templates/pages/home.templ
Add client-side auth redirect as a fallback for authenticated users on the landing page:

```templ
import "{{PROJECT_NAME}}/templates/components/clerk"

templ Home(clerkPublishableKey string) {
    @layouts.Base(meta.PageMeta{Title: "Home"}, clerkPublishableKey) {
        @clerk.AuthRedirect("/dashboard")
        // ... existing home page content ...
    }
}
```

**Note:** Update the Home handler to pass `h.cfg.ClerkPublishableKey` when calling `pages.Home(key)`.

## Update internal/handler/handler.go
Add Clerk auth routes:

```go
func (h *Handler) RegisterRoutes(e *echo.Echo) {
    // ... existing static, health, public routes ...

    // Install Clerk auth middleware globally - verifies JWT and sets clerk_user_id
    e.Use(middleware.ClerkAuth(h.cfg.ClerkSecretKey))

    // Auth pages (public)
    e.GET("/sign-in", h.SignIn)
    e.GET("/sign-up", h.SignUp)

    // Protected routes - RequireClerkAuth checks for clerk_user_id set by ClerkAuth
    protected := e.Group("", middleware.RequireClerkAuth())
    protected.GET("/dashboard", h.Dashboard)
}
```

## Clerk Integration Summary

| Method | Usage |
|--------|-------|
| `Clerk.mountSignIn(el, opts)` | Mount sign-in form |
| `Clerk.mountSignUp(el, opts)` | Mount sign-up form |
| `Clerk.mountUserButton(el)` | Mount user avatar/menu |
| `Clerk.user` | Current user object (null if not signed in) |
| `Clerk.session` | Current session object |

**Key options for mount methods:**
- `forceRedirectUrl` — guarantees redirect after auth (use instead of deprecated `afterSignInUrl`/`afterSignUpUrl`)
- `signUpUrl` / `signInUrl` — cross-links between sign-in and sign-up pages

**References:**
- https://clerk.com/docs/js-frontend/getting-started/quickstart
- https://clerk.com/docs/js-frontend/reference/components/authentication/sign-in
- https://clerk.com/docs/guides/development/customize-redirect-urls

