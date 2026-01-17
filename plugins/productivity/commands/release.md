---
argument-hint: "[patch|minor|major]"
description: "Create a new release with version bump, changelog, and GitHub release"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(jq:*)", "Read", "Edit", "AskUserQuestion"]
---

## Context

- Repository: !`basename $(git rev-parse --show-toplevel)`
- Current version: !`jq -r '.plugins[0].version' .claude-plugin/marketplace.json 2>/dev/null || echo "unknown"`
- Latest tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "No tags found"`
- Commits since last tag: !`git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline 2>/dev/null | wc -l | tr -d ' '`

## Instructions

Create a new release for the gopher-ai plugin marketplace.

### Bump Type

**If `$ARGUMENTS` is provided** (patch, minor, or major), use that bump type.

**If `$ARGUMENTS` is empty**, analyze commits since the last tag to suggest a bump type:
- **major**: Any breaking changes (`BREAKING CHANGE:`, `!:` suffix)
- **minor**: Any new features (`feat:`)
- **patch**: Bug fixes and other changes (`fix:`, `chore:`, `docs:`, etc.)

Ask the user to confirm the bump type using AskUserQuestion before proceeding.

### Workflow

1. **Validate State**
   - Ensure working directory is clean: `git status --porcelain`
   - Ensure we're on the main branch
   - Ensure no uncommitted changes

2. **Calculate New Version**
   - Parse current version from `.claude-plugin/marketplace.json`
   - Apply bump type to get new version (e.g., 1.1.0 → 1.2.0 for minor)

3. **Update Versions**
   - Update ALL version fields in `.claude-plugin/marketplace.json`:
   ```bash
   jq --arg v "NEW_VERSION" '
     .metadata.version = $v |
     .plugins[].version = $v
   ' .claude-plugin/marketplace.json > /tmp/marketplace.json.tmp && \
   mv /tmp/marketplace.json.tmp .claude-plugin/marketplace.json
   ```
   - **IMPORTANT**: Also update each individual `plugin.json` (Claude Code uses these for cache paths):
   ```bash
   for pjson in plugins/*/.claude-plugin/plugin.json; do
     jq --arg v "NEW_VERSION" '.version = $v' "$pjson" > /tmp/pj.tmp && mv /tmp/pj.tmp "$pjson"
   done
   ```

4. **Generate Changelog**
   - Get commits since last tag: `git log LAST_TAG..HEAD --format="%s" --reverse`
   - Group commits by conventional commit type into these categories:
     - **Features** (`feat:`) - New functionality
     - **Bug Fixes** (`fix:`) - Bug fixes
     - **Refactoring** (`refactor:`) - Code changes that neither fix bugs nor add features
     - **Other Changes** (`chore:`, `docs:`, `style:`, `perf:`, `test:`, `ci:`) - Everything else
   - Format as markdown with bullet points, stripping the type prefix for readability
   - Example output:
     ```markdown
     ## What's Changed

     ### Features
     - **(go-workflow)** improve worktree setup with symlinks and recursive env search
     - **(productivity)** add gopher-ai-refresh command

     ### Bug Fixes
     - **(hooks)** use silent exit instead of empty JSON for allow
     - **(go-workflow)** copy loop state files to worktree

     ### Refactoring
     - **(gopher-guides)** make MCP server opt-in to prevent startup slowdown

     **Full Changelog**: https://github.com/OWNER/REPO/compare/vOLD...vNEW
     ```
   - Store the changelog in a variable for use in step 7

5. **Commit and Tag**
   ```bash
   git add .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json
   git commit -m "chore: release vX.Y.Z"
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```

6. **Push to Remote**
   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

7. **Create GitHub Release**
   - Use the changelog generated in step 4
   - Pass it via `--notes` flag (use a heredoc or temp file for multiline content):
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes "$(cat <<'EOF'
   ## What's Changed

   ### Features
   - **(scope)** description

   ### Bug Fixes
   - **(scope)** description

   **Full Changelog**: https://github.com/OWNER/REPO/compare/vOLD...vNEW
   EOF
   )"
   ```
   - **IMPORTANT**: Do NOT use `--generate-notes` - it produces empty changelogs for direct commits

8. **Report Success**
   - Display the release URL
   - Remind user to run `./scripts/refresh-plugins.sh` to update local cache

### Safety Checks

- Never release with uncommitted changes
- Always confirm bump type with user before proceeding
- Verify main branch before releasing
- Check that new version is greater than current version

### Example Usage

- `/release` - Auto-detect bump type from commits
- `/release patch` - Force patch bump (1.1.0 → 1.1.1)
- `/release minor` - Force minor bump (1.1.0 → 1.2.0)
- `/release major` - Force major bump (1.1.0 → 2.0.0)
