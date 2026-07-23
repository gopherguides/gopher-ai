# Codex CLI Detection Correction Design

## Problem

`scripts/install-all.sh` currently marks Codex as available when either a `codex` executable is on `PATH` or `~/.codex/` exists. Prometheus has stale `~/.codex/` state but no Codex executable in non-login or login shells. The universal installer therefore announces Codex as detected, successfully refreshes Claude Code, then aborts when `scripts/install-codex.sh --user` requires the missing command. The exact public installer exits nonzero and never prints its final platform summary.

## Goal

Make the universal installer install only runnable platforms, preserve stale Codex state without modification, and allow other detected platforms to complete successfully when `~/.codex/` exists but the Codex CLI does not.

## Scope

- Detect Codex installation capability only from a resolvable `codex` executable.
- Track the separate condition where `~/.codex/` exists without an executable.
- Print a specific skip warning for that stale-state condition.
- Preserve `~/.codex/` byte-for-byte and do not invoke `scripts/install-codex.sh` when the executable is absent.
- Continue installing Claude Code and Gemini when either is independently detected.
- Add integration regression coverage for a host with Claude Code state, stale Codex state, and no Codex executable.
- Publish the correction as v1.7.4 and rerun the exact public installer locally and on Prometheus.

## Non-Goals

- Installing the Codex CLI itself.
- Searching arbitrary filesystem locations for Codex executables that are not on `PATH`.
- Modifying, deleting, or archiving `~/.codex/`.
- Changing `scripts/install-codex.sh --user` requirements or behavior.
- Installing Gemini on hosts where the Gemini CLI is absent.

## Detection Model

`detect_platforms()` will maintain two independent Codex signals:

- `HAVE_CODEX=true` only when `command -v codex` succeeds.
- `HAVE_CODEX_STATE=true` when `~/.codex/` exists, regardless of executable availability.

The installer will add Codex to the installation platform list and call `install_codex()` only when `HAVE_CODEX=true`. `HAVE_CODEX_STATE` affects user-facing detection output only.

## User-Facing Behavior

`print_detection()` will report one of three Codex states:

- Executable available: `Codex CLI ...... found — will install global plugins to ~/.codex/plugins/`
- No executable but state exists: `Codex CLI ...... skipped (found ~/.codex/ but no codex executable on PATH)`
- Neither executable nor state exists: `Codex CLI ...... skipped (no codex executable on PATH)`

A host with Claude Code and stale Codex state will proceed as a Claude-only installation, exit zero, and print `Done! Installed for: Claude Code`.

## Data Flow

1. Bootstrap the repository if necessary.
2. Detect Claude Code from `~/.claude/`.
3. Detect Codex capability from `command -v codex` and Codex state from `~/.codex/` separately.
4. Detect Gemini from `command -v gemini`.
5. Print the appropriate Codex found or skipped message.
6. Build distributions when Claude Code or Gemini requires them.
7. Invoke only installers whose executable or state requirements are satisfied.
8. Print the final success summary for the platforms actually installed.

## Error Handling

- Missing Codex executable is not an error when another supported platform is available.
- A stale `~/.codex/` directory is never mutated and does not make Codex an installation target.
- If no runnable or supported platform remains, the existing `No supported platforms detected` error remains unchanged.
- A detected Codex executable that later fails remains a real installation error; this correction does not suppress failures from runnable tools.

## Testing

Extend `scripts/test-installation.sh` with an isolated home and controlled `PATH`:

- Create `~/.claude/` and `~/.codex/` under the isolated home.
- Exclude `codex` and `gemini` from the controlled `PATH` while retaining the installer prerequisites.
- Run `scripts/install-all.sh --force` from the repository.
- Require exit zero.
- Require the stale-state skip warning.
- Require no `=== Codex CLI ===` installation section.
- Require the final summary `Done! Installed for: Claude Code`.
- Require the isolated `~/.codex/` directory and a sentinel file inside it to remain unchanged.

The full repository release gate and universal archive verification must pass before publication.

## Release and Host Verification

- Synchronize all marketplace, Claude plugin, and Codex plugin versions to 1.7.4.
- Push a focused PR, require CI and review gates, and squash merge.
- Require a non-empty successful check set for the exact merged main commit.
- Publish v1.7.4 with verified Codex and Gemini archives and PR-generated notes.
- Run `bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"` locally and verify Claude Code, Codex, and Gemini at 1.7.4.
- Run the same exact command on Prometheus and verify a successful Claude-only summary, all seven Claude Code plugin cache roots at 1.7.4, marketplace checkout at the v1.7.4 release SHA, no Codex installation section, and unchanged `~/.codex/` state.
