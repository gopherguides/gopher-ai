---
argument-hint: "[patch|minor|major]"
description: "Create a new release with version bump, changelog, and GitHub release"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(jq:*)", "Read", "Edit", "AskUserQuestion"]
---

## Context

- Repository: !$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "unknown")
- Current version: !$(jq -r '.plugins[0].version' .claude-plugin/marketplace.json 2>/dev/null || echo "unknown")
- Latest tag: !$(git describe --tags --abbrev=0 2>/dev/null || echo "No tags found")
- Commits since last tag: !$(git log "$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0")

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

2. **Detect Changelog Strategy**

   Automatically detect whether the project uses PR-based or direct-commit workflow:

   ```bash
   # Get last tag (or first commit if no tags)
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)

   # Count total commits since last tag
   TOTAL_COMMITS=$(git log ${LAST_TAG}..HEAD --oneline | wc -l | tr -d ' ')

   # Count commits with PR references like (#123)
   PR_COMMITS=$(git log ${LAST_TAG}..HEAD --oneline | grep -E '\(#[0-9]+\)' | wc -l | tr -d ' ')

   # Calculate percentage (avoid division by zero)
   if [ "$TOTAL_COMMITS" -gt 0 ]; then
     PR_PERCENTAGE=$((PR_COMMITS * 100 / TOTAL_COMMITS))
   else
     PR_PERCENTAGE=0
   fi
   ```

   **Decision logic:**
   - If **≥50% of commits** reference PRs → Use **PR-based** (`--generate-notes`)
   - Otherwise → Use **conventional commits** (parse commit messages)

   Report which strategy was detected to the user.

3. **Calculate New Version**
   - Parse current version from `.claude-plugin/marketplace.json`
   - Apply bump type to get new version (e.g., 1.1.0 → 1.2.0 for minor)

4. **Update Versions**
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

   Use the strategy detected in step 2:

   #### Strategy A: PR-Based Workflow (≥50% PR references)

   Use GitHub's auto-generated notes which work well for PR-based repos:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --generate-notes
   ```

   #### Strategy B: Conventional Commits (<50% PR references)

   Generate changelog from commit messages:

   1. Get commits since last tag: `git log LAST_TAG..HEAD --format="%s" --reverse`
   2. Group commits by conventional commit type:
      - **Features** (`feat:`) - New functionality
      - **Bug Fixes** (`fix:`) - Bug fixes
      - **Refactoring** (`refactor:`) - Code changes that neither fix bugs nor add features
      - **Other Changes** (`chore:`, `docs:`, `style:`, `perf:`, `test:`, `ci:`) - Everything else
   3. Format as markdown, stripping type prefix, showing scope in bold
   4. Pass via `--notes` flag:

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

   **Formatting rules for conventional commits:**
   - Parse format: `type(scope): description` or `type: description`
   - Output format: `- **(scope)** description` or `- description` (if no scope)
   - Skip the release commit itself (`chore: release`)
   - Omit empty sections

8. **Build Universal Distribution**
   ```bash
   ./scripts/build-universal.sh
   ```

   Upload platform-specific archives as release assets:
   ```bash
   gh release upload vX.Y.Z dist/gopher-ai-codex-skills-vX.Y.Z.tar.gz
   gh release upload vX.Y.Z dist/gopher-ai-gemini-extensions-vX.Y.Z.tar.gz
   ```

9. **Report Success**
   - Display the release URL
   - Show which changelog strategy was used
   - List uploaded assets (Codex skills, Gemini extensions)
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
