# Step 5: E2E Test Execution via Chrome DevTools MCP

This step performs browser-based E2E testing of web-facing changes. It is optional and silently skips when conditions are not met.

## 5a. Skip Conditions

Skip this entire step (set `E2E_RESULT="skipped"`) if ANY of these are true:

- Chrome DevTools MCP tools are NOT available (check if `mcp__chrome-devtools-mcp__navigate_page` is in the available tools list)
- The project has NO web components (none of the indicators below are present)
- No web-facing files were changed in the diff

**Web component indicators** (at least one must be true):
- `.templ` files exist in the project
- Changed Go files contain HTTP handler patterns: `http.Handler`, `echo.Context`, `gin.Context`, `chi.Router`, `http.HandleFunc`
- `*.html`, `*.tsx`, `*.vue` files exist in the project

**Web-facing change detection:**

```bash
if [ -z "$CHANGED_FILES" ]; then
  CHANGED_FILES=$(git diff --name-only "origin/${BASE_BRANCH}...HEAD")
fi
WEB_CHANGES=$(echo "$CHANGED_FILES" | grep -E '\.(templ|html|tsx|vue|jsx)$' || true)
HANDLER_CHANGES=$(echo "$CHANGED_FILES" | grep '\.go$' | while IFS= read -r f; do
  grep -l -E 'http\.Handler|echo\.Context|gin\.Context|chi\.Router|http\.HandleFunc|http\.ServeMux' "$f" 2>/dev/null
done || true)
```

If both `WEB_CHANGES` and `HANDLER_CHANGES` are empty → skip E2E testing.

## 5b. Detect Dev Server

1. Check for Air config: `.air.toml` or `air.toml` → command: `air`
2. Check `Makefile` for targets: `run`, `serve`, `dev` → command: `make <target>`
3. Check `package.json` scripts: `dev`, `start` → command: `npm run dev` or `npm start`
4. Fallback for Go: `go run ./cmd/*/main.go` or `go run .`

Detect the server port:
- Parse Air config for proxy port or listen port
- Check for `PORT` env var patterns in code
- Check `.env` or `.envrc` for PORT
- Default: `8080` for Go, `3000` for Node, `5173` for Vite

## 5c. Run Database Migrations (if applicable)

**Run migrations BEFORE starting the dev server.** Many apps require up-to-date schema to boot successfully.

```bash
if [ -f Makefile ] && make -qp 2>/dev/null | grep -q '^migrate-up:'; then
  make migrate-up
elif command -v goose >/dev/null 2>&1; then
  goose up
elif command -v migrate >/dev/null 2>&1; then
  migrate -path ./migrations -database "$DATABASE_URL" up
else
  echo "No migration tool detected — skipping migrations"
fi
```

## 5d. Start Dev Server (if not already running)

Check if the port is already in use before starting:

```bash
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[1234]'; then
  echo "Server already running on port $PORT — reusing"
  SERVER_ALREADY_RUNNING=true
else
  $DEV_SERVER_CMD &
  SERVER_PID=$!
  SERVER_ALREADY_RUNNING=false
fi
```

Wait for server readiness (poll up to 30 seconds):

```bash
for i in $(seq 1 30); do
  curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT" 2>/dev/null | grep -qE '^[1234]' && break
  sleep 1
done
```

If server fails to start within 30 seconds → warn ("Dev server failed to start, skipping E2E tests"), set `E2E_RESULT="skipped-server-failed"`, and skip remaining steps. Do NOT block the workflow.

## 5e. Login Flow (if applicable)

Detect if the app requires authentication:

1. Use `mcp__chrome-devtools-mcp__new_page` to open a browser tab
2. Use `mcp__chrome-devtools-mcp__navigate_page` to `http://localhost:$PORT/`
3. Check if the page redirected to a login/auth page (URL contains `/login`, `/sign-in`, `/auth`)

**If login is required:**

1. Look for test credentials in environment files:
   ```bash
   for envfile in .envrc .env .env.local .env.test; do
     if [ -f "$envfile" ]; then
       grep -iE '(TEST_USER|TEST_EMAIL|ADMIN_EMAIL|TEST_PASSWORD|ADMIN_PASSWORD)' "$envfile" 2>/dev/null || true
     fi
   done
   ```
2. If credentials found:
   - Use `mcp__chrome-devtools-mcp__fill_form` with the discovered credentials
   - Use `mcp__chrome-devtools-mcp__click` on the submit/login button
   - Use `mcp__chrome-devtools-mcp__wait_for` to confirm navigation after login
   - Use `mcp__chrome-devtools-mcp__take_screenshot` to capture post-login state
3. If no credentials found: skip login, test only public routes

## 5f. Route Testing

Identify routes from changed files:

1. Parse Go handler registrations for URL patterns (e.g., `mux.HandleFunc("/api/users", ...)`)
2. Parse templ file names to infer page routes
3. If route detection fails, test the root path (`/`) as a baseline

**For each route, execute the test:**

1. **Navigate:** `mcp__chrome-devtools-mcp__navigate_page` to `http://localhost:$PORT<route>`
2. **Screenshot:** `mcp__chrome-devtools-mcp__take_screenshot` to capture the rendered page
3. **Console check:** `mcp__chrome-devtools-mcp__list_console_messages` — check for JavaScript errors
4. **Network check:** `mcp__chrome-devtools-mcp__list_network_requests` — verify no failed requests (5xx responses)
5. **Form interaction** (if the page contains forms related to changed code):
   - Use `mcp__chrome-devtools-mcp__fill` to populate form fields with test data
   - Use `mcp__chrome-devtools-mcp__click` to submit
   - Verify no errors after submission

**Record results** for each page tested: URL, HTTP status, console errors (if any), network failures, screenshot captured.

## 5g. Edge Case Testing

After testing the primary routes, look for edge cases related to the changed code:

1. **Old/new code paths:** If the PR adds a migration or schema change, insert test data that exercises both the old format and new format to verify backwards compatibility
2. **Empty states:** Navigate to pages that may render differently with no data (empty lists, first-time user views)
3. **Error states:** If the PR changes validation or error handling, submit invalid inputs to verify error messages render correctly
4. **Boundary values:** If the PR adds pagination, filters, or limits, test with values at the boundary (0 items, 1 item, max items)

For each edge case tested, record: description, expected behavior, actual behavior, pass/fail.

If test data was inserted for edge case testing, clean it up afterwards to avoid polluting the database.

## 5h. Cleanup

Kill the dev server (only if we started it):

```bash
if [ "$SERVER_ALREADY_RUNNING" != "true" ] && [ -n "$SERVER_PID" ]; then
  kill $SERVER_PID 2>/dev/null || true
fi
```

Collect results:
- `E2E_RESULT`: `pass`, `fail`, `partial`, or `skipped`
- `PAGES_TESTED`: count of routes tested
- Per-route results for the PR comment

**E2E failure handling:**
- Pages returning 500/404 → report as finding but do NOT block
- Console JavaScript errors → report but do NOT block
- MCP tool call fails mid-test → warn and skip remaining E2E tests
- All results are informational — E2E issues are warnings, not gates
