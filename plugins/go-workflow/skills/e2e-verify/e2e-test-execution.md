# Step 5: E2E Test Execution via Chrome DevTools MCP

This step performs browser-based E2E testing of web-facing changes. It is optional and silently skips when conditions are not met.

**CRITICAL PRINCIPLE: Screenshots must be READ, not just captured.** A screenshot you don't look at is worthless. After every `take_screenshot`, you MUST read the image with your vision capabilities, describe what you see, and compare it against the spec/issue requirements. DOM-only checks (console errors, network requests) are supplementary — they do NOT substitute for visual verification.

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

## 5b. Load the Spec (REQUIRED — do this BEFORE any browser testing)

Before touching the browser, understand what you're verifying against. Read the PR description and linked issue to build a mental model of expected visual state:

```bash
gh pr view "$PR_NUM" --json body,title --jq '"\(.title)\n\n\(.body)"'
```

If the PR links to an issue, read those too. Use the GitHub API's structured closing references first (most reliable), then fall back to text parsing:

```bash
# Strategy 1: GitHub's structured closing references (catches all linking methods)
ISSUE_NUMS=$(gh pr view "$PR_NUM" --json closingIssuesReferences --jq '.closingIssuesReferences[].number' 2>/dev/null)

# Strategy 2: Fallback to text parsing (case-insensitive, handles owner/repo#N format)
if [ -z "$ISSUE_NUMS" ]; then
  ISSUE_NUMS=$(gh pr view "$PR_NUM" --json body --jq '.body' | grep -ioE '(closes|fixes|resolves|close|fix|resolve)\s+([a-z0-9/_-]+)?#[0-9]+' | grep -oE '[0-9]+$')
fi

for ISSUE_NUM in $ISSUE_NUMS; do
  gh issue view "$ISSUE_NUM" --json body,title --jq '"\(.title)\n\n\(.body)"' 2>/dev/null
done
```

**Build a checklist** of what the spec says should be visible:
- What pages/routes were added or changed?
- What should they look like? (layout, components, text, styling)
- What user flows were added? (forms, buttons, navigation)
- What acceptance criteria are listed?
- Are there mockups, wireframes, or design descriptions?

This checklist is what you verify screenshots against. If you can't articulate what you expect to see, you can't verify it.

## 5c. Detect Dev Server

1. Check for Air config: `.air.toml` or `air.toml` → command: `air`
2. Check `Makefile` for targets: `run`, `serve`, `dev` → command: `make <target>`
3. Check `package.json` scripts: `dev`, `start` → command: `npm run dev` or `npm start`
4. Fallback for Go: `go run ./cmd/*/main.go` or `go run .`

Detect the server port:
- Parse Air config for proxy port or listen port
- Check for `PORT` env var patterns in code
- Check `.env` or `.envrc` for PORT
- Default: `8080` for Go, `3000` for Node, `5173` for Vite

## 5d. Run Database Migrations (if applicable)

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

## 5e. Start Dev Server (if not already running)

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

## 5f. Login Flow (if applicable)

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
   - **READ the screenshot** — verify you're logged in and see the expected post-login page
3. If no credentials found: skip login, test only public routes

## 5g. Visual Stabilization Protocol

**Before every screenshot**, execute this stabilization sequence to ensure deterministic, accurate captures. Use `mcp__chrome-devtools-mcp__evaluate_script` to run the JavaScript snippets below. If `evaluate_script` is not available, at minimum use `wait_for` with a reasonable timeout before capturing.

1. **Wait for network idle and DOM stability** — inject and execute:
   ```javascript
   // Wait for no in-flight fetch/XHR requests for 500ms
   await new Promise(resolve => {
     let timer = setTimeout(resolve, 500);
     const observer = new PerformanceObserver(() => {
       clearTimeout(timer);
       timer = setTimeout(resolve, 500);
     });
     observer.observe({ entryTypes: ['resource'] });
     // Fallback: resolve after 5s regardless
     setTimeout(resolve, 5000);
   });
   ```

2. **Wait for fonts and images** — inject and execute:
   ```javascript
   await document.fonts.ready;
   await Promise.all(
     Array.from(document.images)
       .filter(img => !img.complete)
       .map(img => new Promise(resolve => { img.onload = img.onerror = resolve; }))
   );
   ```

3. **Disable animations** — inject CSS to freeze all motion:
   ```javascript
   const style = document.createElement('style');
   style.textContent = '*, *::before, *::after { animation-duration: 0s !important; transition-duration: 0s !important; scroll-behavior: auto !important; }';
   document.head.appendChild(style);
   ```

4. **Conditionally blur active element** — only blur if you are NOT testing a focus-dependent state (e.g., form validation errors, keyboard navigation, active input fields). If the current test is verifying a focused state, skip this step:
   ```javascript
   // Skip this if you're testing focus/validation states
   document.activeElement?.blur();
   ```

5. **Brief settle** — allow a final paint:
   ```javascript
   await new Promise(resolve => setTimeout(resolve, 300));
   ```

## 5h. Route Testing (the core of E2E)

Identify routes from changed files:

1. Parse Go handler registrations for URL patterns (e.g., `mux.HandleFunc("/api/users", ...)`)
2. Parse templ file names to infer page routes
3. If route detection fails, test the root path (`/`) as a baseline

**For each route, execute the FULL test sequence:**

### 1. Navigate
`mcp__chrome-devtools-mcp__navigate_page` to `http://localhost:$PORT<route>`

### 2. Stabilize
Run the Visual Stabilization Protocol (section 5g) to ensure the page is fully rendered.

### 3. Screenshot
`mcp__chrome-devtools-mcp__take_screenshot` to capture the rendered page.

### 4. READ THE SCREENSHOT (MANDATORY)

**This is the most important step.** Use your multimodal vision to read the screenshot image and verify:

- **Layout correctness:** Are elements positioned correctly? Is spacing reasonable? Are there overlapping elements or broken layouts?
- **Content presence:** Is the expected text, data, and imagery visible? Are headings, labels, and body text present and readable?
- **Styling:** Are colors, fonts, and visual hierarchy consistent? Does it look like a finished page or a broken one?
- **Component rendering:** Are UI components (buttons, forms, tables, cards, navigation) rendered properly? No missing borders, broken icons, or placeholder text?
- **Image/asset loading:** Are images displayed (not broken image icons)? Are SVGs and icons rendering?
- **Responsive behavior:** Does the layout make sense at the current viewport width? Is anything overflowing or clipped?

**Compare against the spec:** Check each item on the checklist you built in step 5b. If the spec says "add a user table with name and email columns" — verify you see a table with those columns. If the spec says "add a login form" — verify the form fields are visible and labeled correctly.

**Document what you see in detail.** Not just "looks good" — describe the actual visual state:
- "The dashboard shows a navigation sidebar on the left, main content area with a table of 3 users showing name and email columns, header with the app logo"
- "The login form has email and password fields, a 'Sign In' button, and a 'Forgot Password' link below"

**Flag any discrepancies** between what you see and what the spec requires. This is the output that matters.

### 5. Console Check
`mcp__chrome-devtools-mcp__list_console_messages` — check for JavaScript errors. Note: console errors are supplementary to visual verification, not a replacement.

### 6. Network Check
`mcp__chrome-devtools-mcp__list_network_requests` — verify no failed requests (5xx responses). Again, supplementary.

### 7. Form Interaction (if the page contains forms related to changed code)
- Use `mcp__chrome-devtools-mcp__fill` to populate form fields with test data
- Use `mcp__chrome-devtools-mcp__click` to submit
- **Take another screenshot AFTER submission**
- **READ that screenshot** — verify the success/error state matches expectations
- Check console/network for errors

**Record results** for each page tested: URL, visual verification findings (what you saw vs. what was expected), console errors (if any), network failures, spec compliance (pass/fail with explanation).

## 5i. Edge Case Testing

After testing the primary routes, look for edge cases related to the changed code:

1. **Old/new code paths:** If the PR adds a migration or schema change, insert test data that exercises both the old format and new format to verify backwards compatibility
2. **Empty states:** Navigate to pages that may render differently with no data (empty lists, first-time user views)
   - **Screenshot and READ** — verify empty state messaging is present and looks correct
3. **Error states:** If the PR changes validation or error handling, submit invalid inputs to verify error messages render correctly
   - **Screenshot and READ** — verify error messages are visible, properly styled, and informative
4. **Boundary values:** If the PR adds pagination, filters, or limits, test with values at the boundary (0 items, 1 item, max items)

For each edge case tested, record: description, expected behavior, **what you actually saw in the screenshot**, pass/fail.

If test data was inserted for edge case testing, clean it up afterwards to avoid polluting the database.

## 5j. Cleanup

Kill the dev server (only if we started it):

```bash
if [ "$SERVER_ALREADY_RUNNING" != "true" ] && [ -n "$SERVER_PID" ]; then
  kill $SERVER_PID 2>/dev/null || true
fi
```

Collect results:
- `E2E_RESULT`: `pass`, `fail`, `partial`, or `skipped`
- `PAGES_TESTED`: count of routes tested
- Per-route results for the PR comment including **visual verification findings**

**E2E failure handling:**
- Visual discrepancy from spec → report as finding with description of what was expected vs. what was seen
- Pages returning 500/404 → report as finding but do NOT block
- Console JavaScript errors → report but do NOT block
- MCP tool call fails mid-test → warn and skip remaining E2E tests
- All results are informational — E2E issues are warnings, not gates

## Visual Verification Checklist (self-check before completing Step 5)

Before marking E2E testing as complete, confirm ALL of these:

- [ ] I read the PR/issue spec BEFORE starting browser tests
- [ ] I built a checklist of expected visual state from the spec
- [ ] For EVERY screenshot I took, I READ the screenshot image (not just captured it)
- [ ] For EVERY screenshot, I described what I saw in concrete terms
- [ ] I compared what I saw against the spec checklist and noted matches/discrepancies
- [ ] My results include visual findings, not just "screenshot captured"
- [ ] If I found visual discrepancies, I documented them with specific details

**If you cannot check all of these boxes, you have not completed E2E testing.**
