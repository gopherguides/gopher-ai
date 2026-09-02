---
name: avoid-pipefail-quiet-matcher-sigpipe
description: Diagnose intermittent shell assertions where captured output visibly contains the expected text but a quiet matcher pipeline returns failure.
when_to_use: Use when a Bash test enables pipefail and an assertion shaped like printf-to-grep-q intermittently fails, especially as captured output length changes.
---

# Avoid Pipefail Quiet-Matcher SIGPIPE

With `set -o pipefail`, a matcher such as `grep -q` may exit immediately after a match. The upstream producer can then receive `SIGPIPE`, making the pipeline nonzero even though the expected text was present.

Confirm the symptom by printing the captured output when the assertion fails. If the expected value is visible, replace the short-circuit pipeline with input redirection:

```bash
grep -qF "$expected" <<< "$captured_output"
```

For POSIX shell code without here-strings, use a matcher that consumes all input or temporarily avoid `pipefail` only around a narrowly verified assertion. Add predicate-specific diagnostics so process status, filesystem state, output matching, and data validation fail independently.

Stress the focused test with long temporary paths and bounded repetition, then run the authoritative project gate in its CI-like environment.
