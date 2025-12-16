---
argument-hint: "[tag|version]"
description: "Generate changelog from commits since last release"
model: claude-opus-4-5-20251101
allowed-tools: ["Bash", "Read", "Glob", "Grep"]
---

**If `$ARGUMENTS` is empty or not provided:**

Generate a changelog from commits since the last release tag.

**Usage:** `/changelog [starting-point]`

**Examples:**

- `/changelog` - Since last tag
- `/changelog v1.2.0` - Since specific tag
- `/changelog HEAD~50` - Last 50 commits
- `/changelog 2024-01-01` - Since date

**Workflow:**

1. Find the latest git tag
2. Parse commits using Conventional Commits format
3. Group by type (Added, Fixed, Changed, etc.)
4. Generate Keep a Changelog formatted output

Proceed with commits since last tag.

---

**If `$ARGUMENTS` is provided:**

Generate a changelog from git commits since the specified starting point.

## Configuration

- **Since**: `$ARGUMENTS` (tag, commit ref, or date)

## Steps

1. **Identify Release Points**
   - Find the latest tag: `git describe --tags --abbrev=0 2>/dev/null || echo ""`
   - If `$ARGUMENTS` provided, use as starting point
   - If no tags exist, use first commit or a reasonable limit (last 100 commits)

2. **Gather Commits**
   Run: `git log <since>..HEAD --format="%H|%s|%b|%an|%ae" --reverse`

   For each commit, extract:
   - Hash (for linking)
   - Subject line
   - Body (for breaking changes, closes/fixes references)
   - Author info

3. **Parse Conventional Commits**
   Categorize commits into Keep a Changelog sections:

   | Conventional Commit | Changelog Section |
   |---------------------|-------------------|
   | `feat:`, `feature:` | **Added** |
   | `fix:`, `bugfix:`   | **Fixed** |
   | `perf:`             | **Changed** (Performance) |
   | `refactor:`         | **Changed** |
   | `docs:`             | **Changed** (Documentation) |
   | `BREAKING CHANGE:`  | **Changed** (Breaking) |
   | `deprecate:`        | **Deprecated** |
   | `remove:`           | **Removed** |
   | `security:`         | **Security** |
   | `chore:`, `build:`, `ci:`, `test:` | (Skip or group as "Other") |

   For non-conventional commits, use AI to infer category from message content.

4. **Extract References**
   - Look for issue/PR references: `#123`, `fixes #123`, `closes #456`
   - Check commit body for `BREAKING CHANGE:` footer
   - Extract scope from `feat(scope):` patterns

5. **Determine Next Version** (optional)
   If asked, suggest semantic version bump:
   - **Major**: Any `BREAKING CHANGE:` commits
   - **Minor**: Any `feat:` commits
   - **Patch**: Only `fix:` and other non-breaking changes

6. **Generate Changelog**

   Format following Keep a Changelog:

   ```markdown
   ## [Unreleased] - YYYY-MM-DD

   ### Added
   - New feature description (#123)
   - Another feature with scope (auth): description

   ### Changed
   - **BREAKING**: Description of breaking change
   - Performance improvement description
   - Refactored module for clarity

   ### Deprecated
   - Old API endpoint, use /v2/ instead

   ### Removed
   - Removed legacy support for X

   ### Fixed
   - Fixed bug where X happened (#456)
   - Resolved issue with Y

   ### Security
   - Updated dependencies to patch CVE-XXXX
   ```

7. **Output Options**
   - Default: Display formatted changelog
   - If commit count is large (>50), summarize by category counts first
   - Offer to write to CHANGELOG.md (ask user first)
   - Include comparison link if GitHub remote detected: `[Unreleased]: https://github.com/owner/repo/compare/v1.0.0...HEAD`

## Notes

- Skip merge commits unless they contain meaningful info
- Group related commits (e.g., multiple fixes for same issue)
- For breaking changes, provide migration guidance if detectable
- Keep descriptions concise but meaningful
- Preserve original commit author attribution for team projects
- If no conventional commit format, still categorize intelligently
