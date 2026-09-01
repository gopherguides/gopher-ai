# Dockerfile Deployment (Fly.io, self-hosted, or user preference)

## Plugin Resource Contract

`<PLUGIN_ROOT>` denotes the concrete absolute path to the `go-web` plugin directory. Use the
caller's binding when available. If the caller has not bound it, resolve it directly: on Codex,
start from the selected skill's absolute `SKILL.md` path and ascend two directories; on Claude
Code, use the injected plugin root.

Loaded on demand when the user selects the Dockerfile build method. Copy `<PLUGIN_ROOT>/templates/deploy/Dockerfile` to the project root as `Dockerfile` (multi-stage build).

If the project uses SQLite, the final stage needs the SQLite library and a volume for the database:

```dockerfile
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite
# ... same COPY lines ...
VOLUME /app/data
```

**For Fly.io:** also copy `<PLUGIN_ROOT>/templates/deploy/fly.toml` to the project root as `fly.toml`, replacing `{{PROJECT_NAME}}` with the project name.
