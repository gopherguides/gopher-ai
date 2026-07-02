# Dockerfile Deployment (Fly.io, self-hosted, or user preference)

Loaded on demand when the user selects the Dockerfile build method. Copy `${CLAUDE_PLUGIN_ROOT}/templates/deploy/Dockerfile` to the project root as `Dockerfile` (multi-stage build).

If the project uses SQLite, the final stage needs the SQLite library and a volume for the database:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite
# ... same COPY lines ...
VOLUME /app/data
```

**For Fly.io:** also copy `${CLAUDE_PLUGIN_ROOT}/templates/deploy/fly.toml` to the project root as `fly.toml`, replacing `{{PROJECT_NAME}}` with the project name.
