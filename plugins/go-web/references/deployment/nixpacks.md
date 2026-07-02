# Nixpacks Deployment (Railway, Coolify, Dokploy, self-hosted)

Loaded on demand when the user selects the Nixpacks build method. Copy `${CLAUDE_PLUGIN_ROOT}/templates/deploy/nixpacks.toml` to the project root as `nixpacks.toml`.

**CRITICAL Nixpacks rules (learned the hard way):**

1. **Do NOT use `providers = ["go", "node"]`** — dual providers cause npm bash completion conflicts between auto-installed `nodejs_18` and your `nodejs_20`. Manage all packages manually via `nixPkgs` instead.
2. **Always use `nodejs_20`** — `nodejs_22` does NOT exist in most nixpkgs archives. Use `nodejs_20` or plain `nodejs`.
3. **Do NOT add `npm` to `nixPkgs`** — npm is bundled inside `nodejs_20`. Adding `"npm"` as a separate package will fail.
4. **Pin a nixpkgs archive with Go 1.25** — the default archive only has Go 1.22. Use archive `a1bab9e494f5f4939442a57a58d0449a109593fe` which has `go_1_25`. Find archive hashes at https://www.nixhub.io/packages/go.
5. **Use full paths for `go install` binaries in build phase** — `go install` puts binaries in `/root/go/bin/` which is NOT in `$PATH` during the build phase. Always use `/root/go/bin/sqlc`, `/root/go/bin/templ`.
6. **Separate install and build phases** — `go install` needs network access (install phase has it, build phase does not). Put `go install` commands in `[phases.install]`, not `[phases.build]`.
7. **Auto-detection doesn't work for dual-language projects** — Nixpacks sees `go.mod` and ignores `package.json`. You MUST explicitly install Node.js in `nixPkgs`.

If the project uses SQLite, add the SQLite Nix package:

```toml
[phases.setup]
nixpkgsArchive = 'a1bab9e494f5f4939442a57a58d0449a109593fe'
nixPkgs = ["go_1_25", "nodejs_20", "sqlite"]
```

**For Dokploy with SQLite:** Configure a persistent volume so the database survives deploys:

| Setting | Value |
|---------|-------|
| Mount Type | Volume Mount |
| Volume Name | `<project>-data` |
| Mount Path | `/app/data` |

The app's `DATABASE_URL` defaults to `data/<project>.db` which resolves to `/app/data/<project>.db` in the container.

**For Railway:** also copy `${CLAUDE_PLUGIN_ROOT}/templates/deploy/railway.toml` to the project root as `railway.toml`.
