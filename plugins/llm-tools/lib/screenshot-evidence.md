# Screenshot evidence for PR and issue comments

Use this contract for e2e-verify, review-deep, and ship whenever they capture
visual evidence. Requires Python 3 and `gh`; attachment capability is optional.
Resolve `<PLUGIN_ROOT>` to the active installed plugin root before invocation.

## Capture to disk

Chrome DevTools MCP `take_screenshot` accepts `filePath` (absolute or relative
to the MCP server working directory). Always supply the absolute path generated
below, with `format: "png"`. With no filePath it returns image content to the
conversation; do not assume a persistent default filename. Supplying filePath
saves the image instead of returning inline image content, so explicitly open
that saved image for visual inspection.

Claude in Chrome `computer` with `action: "screenshot"` returns an image/ID by
default. If its discovered schema supports `save_to_disk`, set it to true and
copy the actual returned file to the generated path below. It chooses its own
save location; do not assume a path or pass the DevTools `filePath` parameter.
Claude Code versions before 2.1.211 did not reliably persist `save_to_disk`.
Check that the returned file exists and is nonempty. If no disk export is
available, retain the visual findings and record the capture with its missing
file; do not fabricate a path to an image ID. A successful visual inspection
with unavailable disk export is an attachment limitation, not an E2E failure.

Sources checked 2026-09-09:
- [DevTools screenshot implementation](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/src/tools/screenshot.ts)
- [Claude Chrome screenshot persistence](https://code.claude.com/docs/en/chrome#save-screenshots-to-disk)
- [GitHub CLI attachments](https://docs.github.com/en/github-cli/github-cli/attaching-files-with-github-cli)

## One manifest per run

Initialize once, before any capture (including login and edge cases):

```bash
EVIDENCE_RUN=$(python3 "<PLUGIN_ROOT>/scripts/screenshot-evidence.py" init --head "$HEAD_SHA")
```

The helper creates a unique `screenshot-evidence-<short-sha>-<random>/` directory
under `TMPDIR`, then `TMP`, then `TEMP`, then the system temp directory. Keep
`EVIDENCE_RUN` available through posting. Never stage this directory or its
images. Headless workers must post before their temporary directory expires.

For every capture, choose the route path and a unique capture label such as
`desktop-initial`, `mobile-invalid-form`, or `desktop-retest-2`. Omit secrets
from routes/query strings and inspect images for private data before posting.
Do not overwrite earlier failure captures with a passing retest.

```bash
SCREENSHOT_PATH=$(python3 "<PLUGIN_ROOT>/scripts/screenshot-evidence.py" path \
  --run "$EVIDENCE_RUN" --route "$ROUTE" --capture "$CAPTURE")
```

Capture to `SCREENSHOT_PATH`, then READ the image and record the actual verdict:

```bash
python3 "<PLUGIN_ROOT>/scripts/screenshot-evidence.py" record \
  --run "$EVIDENCE_RUN" --route "$ROUTE" --capture "$CAPTURE" --status "$CAPTURE_STATUS"
```

Statuses: `pass`, `fail`, `partial`, `uninspected`. Record missing exports too.
Record each screenshot, not just one per route. The filename is an ASCII route
slug plus the first 16 hex characters of SHA-256 of the JSON route/capture pair.
This distinguishes query strings, punctuation, viewports, and repeated states.
The manifest stores route, capture, and status; filenames, alt text, table rows,
and attachment arguments are all derived from those same records.

## Build and post

Write the complete comment (including its footer and unchanged verification
verdict) to `COMMENT_BODY_FILE`, with exactly one `{{SCREENSHOTS}}` marker where
the Screenshots section belongs. Do not hand-write local Markdown image links.

```bash
python3 "<PLUGIN_ROOT>/scripts/screenshot-evidence.py" post \
  --run "$EVIDENCE_RUN" --body-file "$COMMENT_BODY_FILE" \
  --repo "$REPO_SLUG" --number "$PR_NUM"
```

For an issue comment add `--kind issue` and supply the issue number instead.
An empty initialized run is valid and posts without attachments. Use this same
poster for review-deep's authorized report and ship's smoke-test evidence;
when ship has no PR yet, retain the run and post immediately after PR creation.
On verification failure with an existing PR, post captured evidence before
stopping. Posting never permits a failed verification to proceed.

The poster probes `gh --version` >= 2.99.0 and REST `.permissions.push` for the
explicit target repository. `can_attach` is a boolean consumed by the builder,
never a verification gate. API failures and unknown versions mean unavailable.
For each selected image it builds both `![route-derived alt](images/name.png)`
and a matching `--attach images/name.png#route-derived alt` argument. It runs
`gh pr comment` with `--body-file` from the run directory, so the identical
relative paths resolve. Argument arrays avoid shell expansion. GitHub rewrites
those local references to hosted attachment URLs in place; no local-only note
is included on successful upload.

Non-passing captures precede passes, preserving capture order within each group.
At most 50 existing images are attached. The comment reports total omissions
and non-passing omissions if even failures exceed 50. Missing/empty exports are
counted separately and never produce dead links. Alt text identifies the route,
capture label, and status in both the table and attachment flags.

If preflight is unavailable, replace the entire screenshot section with a short
reason and post text only. If the attachment command fails, retry once with a
text-only section and no image references or attachment flags. A failed request
may have uploaded orphaned assets; do not claim that any image was published.
If the text-only post also fails, report comment delivery failure, preserving
all verification state. Never set or change `E2E_RESULT` because of an upload,
export, or comment-delivery problem. Do not mark a comment as posted on failure.
