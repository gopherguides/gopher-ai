---
argument-hint: "[patch|minor|major]"
description: "Create a new release with version bump, changelog, and GitHub release"
allowed-tools: ["Bash(git:*)", "Bash(gh:*)", "Bash(jq:*)", "Bash(bash:*)", "Bash(tar:*)", "Bash(sleep:*)", "Read", "Edit", "AskUserQuestion"]
---

## Context

- Repository: !`basename \`git rev-parse --show-toplevel 2>/dev/null\` 2>/dev/null || echo "unknown"`
- Current version: !`jq -r '.plugins[0].version' .claude-plugin/marketplace.json 2>/dev/null || echo "unknown"`
- Latest tag: !`git describe --tags --abbrev=0 2>/dev/null || echo "No tags found"`
- Commits since last tag: !`TAG=\`git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD\`; git log "$TAG"..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ' || echo "0"`

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
   - Fetch `origin/main` and require `HEAD` to equal `origin/main`
   - Ensure no uncommitted changes

2. **Detect Changelog Strategy**

   Automatically detect whether the project uses PR-based or direct-commit workflow:

   ```bash
   # Get last tag (or first commit if no tags)
   LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)

   # Count total commits since last tag
   TOTAL_COMMITS=$(git log "$LAST_TAG"..HEAD --oneline | wc -l | tr -d ' ')

   # Count commits with PR references like (#123)
   PR_COMMITS=$(git log "$LAST_TAG"..HEAD --oneline | awk '/\(#[0-9]+\)/ { count++ } END { print count+0 }')

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
   - **IMPORTANT**: Also update each individual `plugin.json` (Claude Code and Codex use these for cache paths):
   ```bash
   for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
     [ -f "$pjson" ] || continue
     jq --arg v "NEW_VERSION" '.version = $v' "$pjson" > /tmp/pj.tmp && mv /tmp/pj.tmp "$pjson"
   done
   ```

   Verify every version source before continuing:

   ```bash
   jq -e --arg v "NEW_VERSION" '
     .metadata.version == $v and all(.plugins[]; .version == $v)
   ' .claude-plugin/marketplace.json >/dev/null

   for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
     [ -f "$pjson" ] || continue
     jq -e --arg v "NEW_VERSION" '.version == $v' "$pjson" >/dev/null
   done
   ```

5. **Validate and Build**

   Run the full repository gate before committing:

   ```bash
   bash -lc './scripts/test-installation.sh && ./scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
   ./scripts/build-universal.sh
   ```

   Assert that the builder's exact archives exist and every packaged manifest
   contains the requested version:

   ```bash
   VERSION="NEW_VERSION"
   CODEX_ASSET="dist/gopher-ai-codex-plugins-v${VERSION}.tar.gz"
   GEMINI_ASSET="dist/gopher-ai-gemini-extensions-v${VERSION}.tar.gz"

   test -f "$CODEX_ASSET"
   test -f "$GEMINI_ASSET"

   CODEX_MANIFESTS=$(tar -tzf "$CODEX_ASSET" | rg '/\.codex-plugin/plugin\.json$')
   test -n "$CODEX_MANIFESTS"
   while IFS= read -r manifest; do
     tar -xOzf "$CODEX_ASSET" "$manifest" | jq -e --arg v "$VERSION" '.version == $v' >/dev/null
   done <<< "$CODEX_MANIFESTS"

   GEMINI_MANIFESTS=$(tar -tzf "$GEMINI_ASSET" | rg '/gemini-extension\.json$')
   test -n "$GEMINI_MANIFESTS"
   while IFS= read -r manifest; do
     tar -xOzf "$GEMINI_ASSET" "$manifest" | jq -e --arg v "$VERSION" '.version == $v' >/dev/null
   done <<< "$GEMINI_MANIFESTS"
   ```

   Stop immediately if any command in this step fails. Do not commit, push,
   tag, draft, or publish a release.

6. **Commit and Push the Release Change**

   ```bash
   git add .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json
   git commit -m "chore: release vX.Y.Z"
   RELEASE_SHA=$(git rev-parse HEAD)
   git push origin HEAD:main
   ```

7. **Wait for Release-Commit CI**

   Poll check runs through GitHub's REST API and require checks for the exact
   release commit. An empty check set is not success.

   ```bash
   CHECKS=""
   for attempt in $(seq 1 24); do
     CHECKS=$(gh api "repos/{owner}/{repo}/commits/${RELEASE_SHA}/check-runs")
     [ "$(jq '.total_count' <<< "$CHECKS")" -gt 0 ] && break
     sleep 5
   done
   test "$(jq '.total_count' <<< "$CHECKS")" -gt 0

   for attempt in $(seq 1 60); do
     CHECKS=$(gh api "repos/{owner}/{repo}/commits/${RELEASE_SHA}/check-runs")
     FAILED=$(jq '[.check_runs[] | select(.status == "completed" and (.conclusion | IN("success", "neutral", "skipped") | not))] | length' <<< "$CHECKS")
     PENDING=$(jq '[.check_runs[] | select(.status != "completed")] | length' <<< "$CHECKS")
     test "$FAILED" -eq 0
     [ "$PENDING" -eq 0 ] && break
     sleep 10
   done

   GREEN_COUNT=$(jq '.total_count' <<< "$CHECKS")
   sleep 10
   CHECKS=$(gh api "repos/{owner}/{repo}/commits/${RELEASE_SHA}/check-runs")
   test "$(jq '[.check_runs[] | select(.status != "completed")] | length' <<< "$CHECKS")" -eq 0
   test "$(jq '[.check_runs[] | select(.conclusion | IN("success", "neutral", "skipped") | not)] | length' <<< "$CHECKS")" -eq 0
   test "$(jq '.total_count' <<< "$CHECKS")" -eq "$GREEN_COUNT"
   test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
   test "$(git ls-remote origin refs/heads/main | awk '{print $1}')" = "$RELEASE_SHA"
   ```

   Stop if checks do not register within two minutes, fail, remain incomplete,
   or if `HEAD` changes. Do not create a tag, draft, or published release.

8. **Create and Verify a Draft Release**

   Use the strategy detected in step 2. Create a draft targeted at the exact
   CI-verified commit and upload both already-verified archives in the same
   command. GitHub creates the tag from that commit when the draft is published.

   #### Strategy A: PR-Based Workflow (≥50% PR references)

   Use GitHub's auto-generated notes which work well for PR-based repos:
   ```bash
   gh release create vX.Y.Z --draft --target "$RELEASE_SHA" --title "vX.Y.Z" --generate-notes "$CODEX_ASSET" "$GEMINI_ASSET"
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
   gh release create vX.Y.Z --draft --target "$RELEASE_SHA" --title "vX.Y.Z" --notes "$(cat <<'EOF'
   ## What's Changed

   ### Features
   - **(scope)** description

   ### Bug Fixes
   - **(scope)** description

   **Full Changelog**: https://github.com/OWNER/REPO/compare/vOLD...vNEW
   EOF
   )" "$CODEX_ASSET" "$GEMINI_ASSET"
   ```

   **Formatting rules for conventional commits:**
   - Parse format: `type(scope): description` or `type: description`
   - Output format: `- **(scope)** description` or `- description` (if no scope)
   - Skip the release commit itself (`chore: release`)
   - Omit empty sections

   Verify the release is still a draft, targets the checked commit, and has
   exactly the expected assets:

   ```bash
   RELEASE=$(gh api --paginate --slurp "repos/{owner}/{repo}/releases" | jq --arg tag "vX.Y.Z" 'add | map(select(.tag_name == $tag)) | first')
   test "$(jq -r '.draft' <<< "$RELEASE")" = "true"
   test "$(jq -r '.target_commitish' <<< "$RELEASE")" = "$RELEASE_SHA"
   jq -e --arg codex "${CODEX_ASSET##*/}" --arg gemini "${GEMINI_ASSET##*/}" '
     (.assets | length) == 2 and
     ([.assets[].name] | sort) == ([$codex, $gemini] | sort)
   ' <<< "$RELEASE" >/dev/null
   RELEASE_ID=$(jq -r '.id' <<< "$RELEASE")
   ```

9. **Publish**

   Publish only the fully verified draft:

   ```bash
   gh api --method PATCH "repos/{owner}/{repo}/releases/${RELEASE_ID}" -F draft=false >/dev/null
   PUBLISHED=$(gh api "repos/{owner}/{repo}/releases/${RELEASE_ID}")
   jq -e --arg tag "vX.Y.Z" --arg codex "${CODEX_ASSET##*/}" --arg gemini "${GEMINI_ASSET##*/}" '
     (.draft | not) and .tag_name == $tag and
     ([.assets[].name] | sort) == ([$codex, $gemini] | sort)
   ' <<< "$PUBLISHED" >/dev/null
   test "$(gh api "repos/{owner}/{repo}/git/ref/tags/vX.Y.Z" --jq '.object.sha')" = "$RELEASE_SHA"
   jq '{draft, tag_name, html_url, assets: [.assets[].name]}' <<< "$PUBLISHED"
   ```

10. **Report Success**
   - Display the release URL
   - Show which changelog strategy was used
   - List uploaded assets (Codex plugins, Gemini extensions)
   - Remind user to run `./scripts/refresh-plugins.sh` to update local cache

### Safety Checks

- Never release with uncommitted changes
- Always confirm bump type with user before proceeding
- Verify main branch before releasing
- Check that new version is greater than current version
- Never create a tag or published release before the release commit's exact CI checks pass
- Never publish a draft until both verified builder-produced assets are attached

### Example Usage

- `/release` - Auto-detect bump type from commits
- `/release patch` - Force patch bump (1.1.0 → 1.1.1)
- `/release minor` - Force minor bump (1.1.0 → 1.2.0)
- `/release major` - Force major bump (1.1.0 → 2.0.0)
