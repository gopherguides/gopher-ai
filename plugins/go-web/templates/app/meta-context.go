package meta

import (
    "context"

    "{{PROJECT_NAME}}/internal/config"
    "{{PROJECT_NAME}}/internal/ctxkeys"
)

func SiteFromCtx(ctx context.Context) config.SiteConfig {
    if cfg, ok := ctx.Value(ctxkeys.SiteConfig).(config.SiteConfig); ok {
        return cfg
    }
    return config.SiteConfig{Name: "{{PROJECT_NAME}}"}
}

func SiteNameFromCtx(ctx context.Context) string {
    return SiteFromCtx(ctx).Name
}

func SiteURLFromCtx(ctx context.Context) string {
    return SiteFromCtx(ctx).URL
}
