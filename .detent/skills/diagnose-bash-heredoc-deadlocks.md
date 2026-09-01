---
name: diagnose-bash-heredoc-deadlocks
description: Diagnose sandboxed macOS shell tests that hang while Bash writes a here-document fixture, and rerun them with the repository's compatible interpreter.
when_to_use: Use when a managed shell-test session produces no output and a bounded trace stops at a `cat` command that writes a here-document, especially when multiple Bash installations are available.
---

# Diagnose Bash Here-Document Deadlocks

Reuse the stalled managed session long enough to establish that it is not merely
slow, then stop it before tracing. Do not launch duplicate test processes while
the original session is active.

Run a bounded `bash -x` trace with `gtimeout` or `timeout`. If the final trace
line is the `cat` that writes a here-document fixture and the destination stays
an empty regular file, isolate the same here-document in the Detent-provided
temporary directory.

Compare the available interpreters explicitly:

```bash
/opt/homebrew/bin/bash --version | sed -n '1p'
/bin/bash --version | sed -n '1p'
```

Run the isolated reproduction once with each interpreter under the same bounded
timeout. When the repository-declared `/bin/bash` succeeds and Homebrew Bash
hangs, keep `/bin` first while retaining required tool directories later in
`PATH`, then rerun the original validation command unchanged inside `/bin/bash`.

```bash
env PATH=/bin:/usr/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin \
  /bin/bash -lc '<original validation command>'
```

Keep every reproduction and fixture under `TMPDIR`, `TMP`, or `TEMP` supplied by
Detent. Do not edit an unrelated test merely to hide an interpreter-specific
hang. Record the interpreter evidence and the successful authoritative command
in the handoff.
