package config

import (
    "log/slog"
    "os"
)

type SiteConfig struct {
    Name           string
    URL            string
    DefaultOGImage string
}

type Config struct {
    DatabaseURL string
    Port        string
    Env         string
    Site        SiteConfig
    // Add service keys based on selection:
    // ClerkSecretKey      string
    // ClerkPublishableKey string
    // BrevoAPIKey         string
    // StripeSecretKey     string
    // StripePublishableKey string
    // StripeWebhookSecret string
}

func Load() *Config {
    cfg := &Config{
        DatabaseURL: os.Getenv("DATABASE_URL"),
        Port:        getEnvOrDefault("PORT", "3000"),
        Env:         getEnvOrDefault("ENV", "development"),
        Site: SiteConfig{
            Name:           getEnvOrDefault("SITE_NAME", "{{PROJECT_NAME}}"),
            URL:            getEnvOrDefault("SITE_URL", "http://localhost:3000"),
            DefaultOGImage: getEnvOrDefault("DEFAULT_OG_IMAGE", "/static/images/og-default.png"),
        },
    }

    if cfg.DatabaseURL == "" {
        slog.Error("DATABASE_URL environment variable is required")
        os.Exit(1)
    }

    return cfg
}

func (c *Config) IsDevelopment() bool {
    return c.Env == "development"
}

func (c *Config) IsProduction() bool {
    return c.Env == "production"
}

func getEnvOrDefault(key, defaultValue string) string {
    if value := os.Getenv(key); value != "" {
        return value
    }
    return defaultValue
}
