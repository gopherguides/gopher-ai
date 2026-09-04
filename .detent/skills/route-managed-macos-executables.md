---
name: route-managed-macos-executables
description: Keep shell and Go validation moving when managed macOS workers cannot directly execute files created in the workspace or Detent temporary directory.
when_to_use: Use when an executable script or freshly built Go binary hangs in a managed Darwin worker, while invoking the script through /bin/bash succeeds.
---

# Route Managed macOS Executables

Confirm the failure with a bounded direct invocation, then run the same shell
script through `/bin/bash`. Update repository-owned callers to use the explicit
interpreter, including nested helpers and commands launched from Python.

For executable command fixtures resolved through `PATH`, omit the shebang when
the test shell can safely rely on its `ENOEXEC` fallback. Keep the fixture body
portable to that shell.

Freshly linked Go test binaries can have the same managed-worker restriction.
On Darwin only when the temporary directory is beneath the repository's
`.detent/tmp`, use `go test -c` with output under that temporary directory. Run
the normal `go test` command everywhere else so Linux CI retains runtime
coverage.

Add a source-contract regression for each routed boundary and rerun the
authoritative gate through `/bin/bash`. Do not generalize compile-only behavior
beyond the detected managed Darwin environment.
