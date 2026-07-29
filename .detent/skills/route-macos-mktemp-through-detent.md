---
name: route-macos-mktemp-through-detent
description: Route repository scripts that call bare macOS mktemp into Detent's writable temporary directory without changing the script.
when_to_use: Use when a sandboxed macOS command reports mkstemp permission errors under the Darwin host temp directory even though TMPDIR, TMP, and TEMP point at .detent/tmp.
---

# Route macOS `mktemp` Through Detent

Confirm `TMPDIR`, `TMP`, and `TEMP` point inside the Detent workspace and that
the directory is writable.

Prefer an explicit template for commands you control:

```bash
/usr/bin/mktemp "${TMPDIR:?}/task-name.XXXXXX"
```

If an in-scope repository script uses bare `mktemp`, changing that script is
out of scope, and the script is safe to source, bind `mktemp` in a child Bash
process:

```bash
bash -c 'mktemp() { /usr/bin/mktemp "${TMPDIR:?}/task-name.XXXXXX"; }; source "$1"' _ ./path/to/script.sh
```

Read the script first. Do not source it when it depends on `$0`, intentionally
calls `exit`, or assumes a fresh process. In that case, stop and choose a
wrapper approach that preserves subprocess semantics. Never fall back to the
host temp directory.
