# Step 6: Post E2E Results as PR Comment

## 6a. Build Comment Body

Construct a structured markdown comment using the results from Steps 1-5:

```markdown
## E2E Verification Results

**Mode:** $MODE
**Branch:** $BRANCH (rebased onto $BASE_BRANCH)
**Commit:** $HEAD_SHA

### Build Verification

| Check | Result |
|-------|--------|
| Code generation | $GEN_RESULT (pass/fail/skipped) |
| `go build` | $BUILD_RESULT (pass/fail) |
| `go test` | $TEST_RESULT (pass/fail) |
| `golangci-lint` | $LINT_RESULT (pass/fail/skipped) |

### E2E Visual Verification Results

| Route | Visual Status | Spec Match | Console Errors | Network Errors |
|-------|--------------|------------|----------------|----------------|
| / | Rendered correctly | Yes — matches spec | None | None |
| /dashboard | Layout issue | No — missing sidebar | None | None |
| ... | ... | ... | ... | ... |

**Pages tested:** $PAGES_TESTED

*Count spec matches and discrepancies from the Visual Verification Findings below.*

### Visual Verification Findings

For each page tested, include a detailed description of what was visually observed and how it compares to the spec:

**Route: /**
- **Expected (from spec):** Homepage with hero section, navigation bar, and feature cards
- **Observed:** Hero section renders with correct heading and CTA button. Navigation bar shows all 4 links. Feature cards display in a 3-column grid. All images loaded.
- **Verdict:** PASS — matches spec

**Route: /dashboard**
- **Expected (from spec):** User dashboard with sidebar navigation and data table
- **Observed:** Data table renders correctly with 3 columns. However, sidebar navigation is missing — only the main content area is visible. The layout appears to be full-width instead of the expected sidebar + content split.
- **Verdict:** FAIL — sidebar navigation missing from layout

*Each route MUST include Expected/Observed/Verdict. "Screenshot captured" is NOT a valid finding.*

### Screenshots

| Page | Screenshot |
|------|-----------|
| / | ![homepage](screenshot-homepage.png) |
| /dashboard | ![dashboard](screenshot-dashboard.png) |

*Screenshots saved locally. See Visual Verification Findings above for what was observed in each screenshot.*

### Edge Cases Tested

| Case | Expected | Observed | Result |
|------|----------|----------|--------|
| Empty list view | Shows "no items" message | "No items found" text centered in empty table body | PASS |
| Invalid form input | Shows validation error | Red border on email field, "Invalid email" message below | PASS |

*Edge case section only appears if edge cases were tested in Step 5i.*
*The "Observed" column MUST describe what was actually seen in the screenshot, not just "Rendered correctly".*

### Summary

$OVERALL_VERDICT
```

**Conditional sections:**
- If E2E was skipped (MCP unavailable or no web components): replace the E2E Visual Verification Results section with: `*E2E tests skipped: $SKIP_REASON*`
- If build failed: add a prominent warning at the top: `> **Build failed — E2E tests were not run.**`
- If investigate mode: add an "Investigation Findings" section with gap analysis

**Quality gate for the comment:** Before posting, verify that:
- Every tested route has Expected/Observed/Verdict entries (not just "captured" or "pass")
- The Observed column contains actual visual descriptions (what elements were seen, their layout, their content)
- Any discrepancies between Expected and Observed are called out clearly

## 6b. Post Comment

```bash
gh pr comment "$PR_NUM" --body "$(cat <<'EOF'
<constructed comment body>
EOF
)"
```

## 6c. Mode-Specific Footer

Append mode-specific information to the comment:

| Mode | Footer |
|------|--------|
| `verify` | "Verification complete. Ready for review." |
| `fix-and-verify` | "Review feedback addressed and verified. `run-full-ci` label added." |
| `investigate` | "Investigation complete. See findings above." |
| `ship-prep` | "Ship prep complete. `run-full-ci` label added. Ready for `/ship`." |
| `ship` | "Verified and shipping via `/ship`." |
| `fix-and-ship` | "Review addressed, verified, and shipping. `run-full-ci` label added." |

## 6d. Add Labels (mode-specific)

For modes that add the `run-full-ci` label (`fix-and-verify`, `ship-prep`, `fix-and-ship`):

```bash
gh pr edit "$PR_NUM" --add-label "run-full-ci"
```

For all modes where E2E passed, optionally add:

```bash
gh pr edit "$PR_NUM" --add-label "e2e-verified"
```

**Note:** If labels don't exist in the repo, the `gh pr edit --add-label` command will create them automatically.
