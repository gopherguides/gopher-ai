# Dockerfile Deployment (Fly.io, self-hosted, or user preference)

## Plugin Resource Contract

`<PLUGIN_ROOT>` denotes the concrete absolute path to the `go-web` plugin directory. On Claude
Code, bind it to the injected plugin root. On Codex, inherit the root resolved by the calling
skill.

Loaded on demand when the user selects the Dockerfile build method. Copy `<PLUGIN_ROOT>/templates/deploy/Dockerfile` to the project root as `Dockerfile` (multi-stage build).

If the project uses SQLite, the final stage needs the SQLite library and a volume for the database:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite
# ... same COPY lines ...
VOLUME /app/data
```

**For Fly.io:** also copy `<PLUGIN_ROOT>/templates/deploy/fly.toml` to the project root as `fly.toml`, replacing `{{PROJECT_NAME}}` with the project name.
