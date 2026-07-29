---
name: verify-mcp-stdio-compatibility
description: Verify a pinned STDIO MCP server across modern and legacy protocol eras.
when_to_use: Use when auditing or pinning an MCP server after a protocol revision changes initialization or discovery.
---

# Verify MCP STDIO Compatibility

1. Query the package registry for the latest version, publication time, source
   repository, and MCP SDK dependency.
2. Download the exact artifact into the configured temporary directory and
   inspect the published code rather than relying on repository main.
3. Start the pinned command with an isolated npm cache under `TMPDIR`.
4. Send `server/discover` with the preferred modern protocol version and the
   required per-request `_meta`.
5. Classify the response using the specification:
   - A discovery result identifies a modern server.
   - A recognized modern version error requires retrying a supported version.
   - Any other error or timeout identifies a legacy server.
6. For a legacy server, send `initialize`, then
   `notifications/initialized`, followed by `tools/list`.
7. Assert every tool referenced by the consuming plugin is advertised. Do not
   rely on a documented tool count when source references can be enumerated.
8. Capture non-JSON stdout separately from stderr because STDIO MCP requires
   stdout to contain protocol messages only.
9. Verify at least one current client from each supported client family can
   connect through an isolated configuration.
10. Document the negotiated protocol, unsupported modern version, exact pin,
    and non-MCP fallback behavior.
