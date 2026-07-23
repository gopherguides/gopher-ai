# Codex Legacy Marketplace Migration Design

## Problem

The v1.7.2 installer registers and upgrades the Git-backed `gopher-ai` Codex marketplace, but prior user installations can leave `~/.agents/plugins/marketplace.json` behind. Codex discovers both marketplaces under the same `gopher-ai` name and may resolve plugins from the legacy local marketplace first. Its sources point to removed `~/.codex/plugins/<name>` directories, causing `codex plugin add <name>@gopher-ai` to fail even though the Git marketplace and versioned cache are valid.

## Goal

Make `scripts/install-codex.sh --user` safely migrate an installer-owned legacy user marketplace to the Git-backed marketplace, preserve user-authored state, roll back on failure, and allow `scripts/install-all.sh` upgrades to complete without manual cleanup.

## Scope

- Detect the legacy marketplace at `~/.agents/plugins/marketplace.json`.
- Establish ownership from the marketplace's JSON structure rather than its path alone.
- Temporarily remove an owned legacy marketplace before Codex resolves marketplace names.
- Restore the legacy marketplace and existing cache roots if any Git marketplace or plugin installation step fails.
- Permanently retire the legacy marketplace only after every Codex plugin installs successfully.
- Add regression coverage for migration, rollback, duplicate resolution, and ownership safeguards.
- Release the correction as v1.7.3 and verify the exact public installer locally and on Prometheus.

## Non-Goals

- Migrating arbitrary user-authored Codex marketplaces.
- Rewriting Codex CLI marketplace resolution behavior.
- Removing unrelated files under `~/.agents/plugins` or `~/.codex/plugins`.
- Changing repository-scoped `--repo` installation behavior.

## Ownership Rules

The installer may migrate `~/.agents/plugins/marketplace.json` only when all of these conditions hold:

- The file is valid JSON.
- Its top-level `name` is `gopher-ai`.
- It contains at least one plugin.
- Every plugin name is one of the Codex-capable Gopher AI plugins shipped by the current repository.
- Every plugin source is local and points to `./.codex/plugins/<plugin-name>` with the path name matching the plugin name.

A malformed file, unknown plugin, mixed marketplace, non-local source, or mismatched path is not installer-owned. The installer leaves such a file unchanged and exits with an actionable error if it would conflict with the `gopher-ai` Git marketplace.

## Migration Flow

1. Bootstrap the repository and identify the current Codex-capable plugin names.
2. Inspect `~/.agents/plugins/marketplace.json` before calling `codex plugin marketplace list`.
3. If the file is absent or is not named `gopher-ai`, continue unchanged.
4. If it is named `gopher-ai` and passes every ownership rule, move it to a temporary backup and record the original path.
5. If it is named `gopher-ai` but fails an ownership rule, stop without altering it.
6. Back up existing published Gopher AI cache roots using the current cache transaction.
7. List configured marketplaces, then register or upgrade the Git-backed `gopher-ai` marketplace.
8. Install all Codex-capable plugins through `codex plugin add <name>@gopher-ai`.
9. If any marketplace or plugin CLI operation fails, restore the cache roots and move the legacy marketplace backup back to its original path byte-for-byte.
10. After all plugins install successfully, discard the temporary legacy marketplace backup, retain the new versioned cache, and run the existing cleanup for owned direct-install plugin directories and legacy skills.

## Components

### Legacy Marketplace Detection

A focused function validates the candidate file with `jq` and the current repository's Codex-capable plugin set. It returns distinct outcomes for absent, owned, and conflicting files so callers can preserve uncertain state and report useful errors.

### Transactional Backup

A backup function moves the owned marketplace file into a private temporary directory and records both paths. A restore function is idempotent and moves the exact file back when installation fails. Successful installation removes the temporary backup through the existing exit cleanup mechanism without restoring it.

### Installation Integration

`install_user_plugins` begins the marketplace transaction before querying Codex. Existing cache backup and restoration remain in place. Every early return after the transaction starts restores both resources in a consistent order.

## Error Handling

- Invalid or uncertain marketplace ownership stops the install before any marketplace or cache mutation.
- Git marketplace registration or upgrade failure restores the legacy marketplace and cache roots.
- Any individual plugin installation failure restores the legacy marketplace and cache roots.
- Restore operations are idempotent so the normal exit trap cannot corrupt a completed rollback.
- Errors identify the conflicting path and explain that it was preserved because ownership could not be proven.

## Testing

Extend `scripts/test-installation.sh` with isolated homes and the existing mocked Codex CLI to verify:

- An owned legacy marketplace creates the duplicate-name reproduction before migration and installation succeeds after migration.
- The owned legacy marketplace is absent after a fully successful install.
- A marketplace upgrade failure restores the original file byte-for-byte.
- A plugin installation failure restores the original file byte-for-byte and preserves prior cache roots.
- A malformed marketplace is preserved and rejected.
- A `gopher-ai` marketplace containing an unknown plugin is preserved and rejected.
- A marketplace with a mismatched plugin path is preserved and rejected.
- An unrelated marketplace file is untouched.
- A clean host without the legacy file continues through the existing installation path.

The full repository release gate and universal archive verification must pass before publishing v1.7.3.

## Release and Host Verification

- Synchronize every marketplace, Claude plugin, and Codex plugin manifest to 1.7.3.
- Run the repository release gate and build verified Codex and Gemini archives.
- Commit and push the fix and version bump, require exact-commit CI success, create a verified draft with both assets, and publish v1.7.3.
- Run `bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"` locally and verify Claude Code, Codex, and Gemini complete successfully at 1.7.3.
- Run the same command over SSH on Prometheus and verify the installed versions there.
