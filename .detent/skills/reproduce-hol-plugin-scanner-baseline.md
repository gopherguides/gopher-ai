---
name: reproduce-hol-plugin-scanner-baseline
description: Reproduce a pinned HOL Plugin Scanner CI result with equivalent runtime integrations and isolated artifacts.
when_to_use: Use when a local HOL Plugin Scanner score or finding set differs from a pinned GitHub Actions run.
---

# Reproduce a HOL Plugin Scanner Baseline

1. Read the calling workflow and pinned scanner action to capture the Python
   version, scanner package version, policy profile, score threshold, severity
   gate, and Cisco integration settings.
2. Use the same Python minor version as CI. Do not accept a scan whose
   integration summary says Cisco evidence is unavailable; newer Python
   versions can silently omit that evidence and change the score.
3. Install the pinned scanner into an isolated environment under `TMPDIR`. If
   the host interpreter is broken or mismatched, use a temporary `uv`-managed
   interpreter instead of changing the host toolchain.
4. Export the target revision with `git archive` into a unique directory below
   `TMPDIR` so the baseline contains only tracked files from that revision.
5. Run the scanner from a separate temporary working directory while passing
   the exported plugin path explicitly. This contains scanner session files
   such as `:memory:.ses` outside the repository.
6. Match every CI scan flag and capture a JSON report even when the threshold
   makes the command exit nonzero.
7. Record the interpreter version, scanner version, exit status, score,
   integration statuses, and full high-severity finding identities. Compare
   those fields before treating local output as equivalent to CI.
