# Start-Issue CI Monitoring

Run the shared REST monitor in the selected worktree. Capture the published
local head after pushing; never substitute an unrelated remote head.

```bash
PUBLISHED_HEAD_SHA=$(git -C "$WORKTREE_PATH" rev-parse HEAD)
CI_STATUS=0
(cd "$WORKTREE_PATH" &&
  source "<PLUGIN_ROOT>/lib/github-rest.sh" &&
  GITHUB_CHECK_POLL_SECONDS=60 github_watch_pr_checks "$PR_NUM" "$PUBLISHED_HEAD_SHA") || CI_STATUS=$?
```

The helper reads paginated check runs and commit statuses for that SHA, waits
for registration and a stable terminal check set, and rechecks the PR head
before reporting success. It uses REST with a fixed 60-second polling interval.

Handle `CI_STATUS` explicitly:

- `0`: all registered checks passed, with a stable set and unchanged PR head.
- `1`: inspect the emitted failing checks, fix, verify, commit, push, and monitor
  the newly published head.
- `2`: checks did not register. Inspect CI configuration; do not claim success.
- `3`: API failure. Honor any server retry delay and wait at least 60 seconds
  before retrying; never treat unavailable checks as passing.
- `4`: PR head changed. Reconcile the published commit with the remote before
  starting another monitor; previous results do not verify the new head.
- `5`: terminal wait timed out. Report pending checks and preserve incomplete
  state; do not claim success.

Do not wrap the monitor in an immediate retry loop. Any unresolved nonzero
result follows the start-issue incomplete result contract with reason
`start-issue-ci-unverified`.
