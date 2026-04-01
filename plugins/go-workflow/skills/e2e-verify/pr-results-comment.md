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

### E2E Test Results

| Route | Status | Console Errors | Network Errors | Screenshot |
|-------|--------|---------------|----------------|------------|
| / | 200 OK | None | None | captured |
| /dashboard | 200 OK | None | None | captured |
| ... | ... | ... | ... | ... |

**Pages tested:** $PAGES_TESTED | **Passed:** $PAGES_PASSED | **Errors:** $PAGES_ERRORED

### Screenshots

| Page | Screenshot |
|------|-----------|
| / | ![homepage](screenshot-homepage.png) |
| /dashboard | ![dashboard](screenshot-dashboard.png) |

*Screenshots saved locally. Refer to descriptions above for visual verification results.*

### Edge Cases Tested

| Case | Expected | Actual | Result |
|------|----------|--------|--------|
| Empty list view | Shows "no items" message | Rendered correctly | PASS |
| Invalid form input | Shows validation error | Error displayed | PASS |

*Edge case section only appears if edge cases were tested in Step 5g.*

### Summary

$OVERALL_VERDICT
```

**Conditional sections:**
- If E2E was skipped (MCP unavailable or no web components): replace the E2E Test Results section with: `*E2E tests skipped: $SKIP_REASON*`
- If build failed: add a prominent warning at the top: `> **Build failed — E2E tests were not run.**`
- If investigate mode: add an "Investigation Findings" section with gap analysis

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
