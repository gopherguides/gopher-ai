# Codex CLI Detection Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the universal installer skip stale Codex state when no executable is available, publish v1.7.4, and complete exact installer runs locally and on Prometheus.

**Architecture:** `scripts/install-all.sh` will separate executable capability from persisted Codex state. Only a resolvable executable makes Codex an installation target; stale state changes the detection message but is never modified.

**Tech Stack:** Bash, `jq`, shellcheck, isolated-home integration tests, Git/GitHub CLI, existing release scripts.

## Global Constraints

- Set `HAVE_CODEX=true` only when `command -v codex` succeeds.
- Preserve `~/.codex/` unchanged when the Codex executable is absent.
- Print `Codex CLI ...... skipped (found ~/.codex/ but no codex executable on PATH)` for stale state without a CLI.
- Continue installing other detected platforms and print a successful summary for those platforms.
- Keep `scripts/install-codex.sh --user` behavior unchanged.
- Synchronize `.claude-plugin/marketplace.json`, every Claude plugin manifest, every Codex plugin manifest, and every generated Gemini extension manifest to 1.7.4.
- Keep the existing unversioned Codex marketplace schema; do not add a top-level version to the generated Codex `marketplace.json`.
- Treat only `.claude-plugin/marketplace.json`, Claude plugin manifests, Codex plugin manifests, and Gemini extension manifests as version-bearing.
- Publish only after PR CI/review gates and exact merged-main CI pass.
- Run the user's exact public installer command locally and on Prometheus after publication.

---

### Task 1: Correct Codex Detection with an Integration Regression

**Files:**
- Modify: `scripts/install-all.sh:124-167`
- Modify: `scripts/test-installation.sh:495-527`

**Interfaces:**
- Consumes: `HOME`, `PATH`, existing `HAVE_CLAUDE`, `HAVE_CODEX`, and `HAVE_GEMINI` platform flags.
- Produces: `HAVE_CODEX_STATE` boolean used only for user-facing detection output.

- [ ] **Step 1: Add the failing stale-state integration regression**

Insert after the existing `install-all.sh fails cleanly when jq is missing` test:

```bash
echo -n "install-all.sh skips stale Codex state when the CLI is unavailable... "
TMP_HOME=$(mktemp -d)
TMP_BIN=$(mktemp -d)
mkdir -p "$TMP_HOME/.claude" "$TMP_HOME/.codex"
printf '%s\n' 'preserve me' > "$TMP_HOME/.codex/SENTINEL"
for cmd in bash sh awk sed grep find mkdir rm cp mv cmp mktemp printf cat dirname basename tr head tail xargs sleep date wc sha256sum shasum git sort uniq stat ln readlink jq comm touch chmod cut id env true false echo test tar tree; do
  cmd_path="$(command -v "$cmd" 2>/dev/null || true)"
  [ -n "$cmd_path" ] && ln -s "$cmd_path" "$TMP_BIN/$cmd"
done
set +e
HOME="$TMP_HOME" PATH="$TMP_BIN" bash "$ROOT_DIR/scripts/install-all.sh" --force \
  </dev/null >/tmp/gopher-ai-installall-stale-codex.log 2>&1
STALE_CODEX_EXIT=$?
set -e
if [ "$STALE_CODEX_EXIT" -ne 0 ]; then
  echo "FAIL (Claude-only install exited non-zero)"
  sed -n '1,80p' /tmp/gopher-ai-installall-stale-codex.log
  ERRORS=$((ERRORS + 1))
elif ! grep -Fq 'Codex CLI ...... skipped (found ~/.codex/ but no codex executable on PATH)' /tmp/gopher-ai-installall-stale-codex.log; then
  echo "FAIL (stale Codex state warning was missing)"
  ERRORS=$((ERRORS + 1))
elif grep -Fq '=== Codex CLI ===' /tmp/gopher-ai-installall-stale-codex.log; then
  echo "FAIL (Codex installer ran without a Codex executable)"
  ERRORS=$((ERRORS + 1))
elif ! grep -Fq 'Done! Installed for: Claude Code' /tmp/gopher-ai-installall-stale-codex.log; then
  echo "FAIL (Claude-only completion summary was missing)"
  ERRORS=$((ERRORS + 1))
elif [ "$(cat "$TMP_HOME/.codex/SENTINEL")" != 'preserve me' ]; then
  echo "FAIL (stale Codex state was modified)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -rf "$TMP_HOME" "$TMP_BIN"
```

- [ ] **Step 2: Run the installation suite and verify RED**

Run:

```bash
./scripts/test-installation.sh
```

Expected: the new regression fails because the current installer enters `=== Codex CLI ===` and exits with `error: required command not found: codex`; existing tests continue running.

- [ ] **Step 3: Separate executable detection from stale state**

Replace the Codex portion of `detect_platforms()` with:

```bash
    HAVE_CODEX=false
    HAVE_CODEX_STATE=false

    if command -v codex >/dev/null 2>&1; then
        HAVE_CODEX=true
    fi
    if [[ -d "$HOME/.codex" ]]; then
        HAVE_CODEX_STATE=true
    fi
```

Keep the existing Claude and Gemini detection unchanged.

- [ ] **Step 4: Print distinct Codex skip states**

Replace the Codex branch in `print_detection()` with:

```bash
    if $HAVE_CODEX; then
        echo "  Codex CLI ...... found — will install global plugins to ~/.codex/plugins/"
    elif $HAVE_CODEX_STATE; then
        echo "  Codex CLI ...... skipped (found ~/.codex/ but no codex executable on PATH)"
    else
        echo "  Codex CLI ...... skipped (no codex executable on PATH)"
    fi
```

Do not change platform-list construction or `install_codex()` invocation; both already depend on `HAVE_CODEX`.

- [ ] **Step 5: Run focused verification**

Run:

```bash
bash -n scripts/install-all.sh
shellcheck scripts/install-all.sh scripts/test-installation.sh
./scripts/test-installation.sh
git diff --check
```

Expected: all commands exit zero, the stale-state regression prints `OK`, and the installation suite ends with `All installation tests passed.`

- [ ] **Step 6: Commit the detection fix**

Run:

```bash
git add scripts/install-all.sh scripts/test-installation.sh
git commit -m "fix(install): require Codex executable"
```

---

### Task 2: Bump and Validate v1.7.4

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/*/.claude-plugin/plugin.json`
- Modify: `plugins/*/.codex-plugin/plugin.json`
- Generate: `dist/gemini/gopher-ai-*/gemini-extension.json`

**Interfaces:**
- Consumes: Task 1's approved detection fix.
- Produces: all version-bearing manifests and both release archives at 1.7.4.
- Preserves: the existing unversioned generated Codex marketplace schema with no top-level version.

- [ ] **Step 1: Synchronize all manifest versions**

Run:

```bash
VERSION=1.7.4
jq --arg v "$VERSION" '.metadata.version = $v | .plugins[].version = $v' \
  .claude-plugin/marketplace.json > /tmp/marketplace.json.tmp
mv /tmp/marketplace.json.tmp .claude-plugin/marketplace.json
for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
  [ -f "$pjson" ] || continue
  jq --arg v "$VERSION" '.version = $v' "$pjson" > /tmp/plugin.json.tmp
  mv /tmp/plugin.json.tmp "$pjson"
done
jq -e --arg v "$VERSION" '.metadata.version == $v and all(.plugins[]; .version == $v)' \
  .claude-plugin/marketplace.json >/dev/null
for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
  [ -f "$pjson" ] || continue
  jq -e --arg v "$VERSION" '.version == $v' "$pjson" >/dev/null
done
```

- [ ] **Step 2: Run the full repository release gate**

Run:

```bash
bash -lc './scripts/test-installation.sh && ./scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
```

- [ ] **Step 3: Build and verify release archives**

Run:

```bash
./scripts/build-universal.sh
VERSION=1.7.4
CODEX_ASSET="dist/gopher-ai-codex-plugins-v${VERSION}.tar.gz"
GEMINI_ASSET="dist/gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
test -f "$CODEX_ASSET"
test -f "$GEMINI_ASSET"
CODEX_MANIFESTS=$(tar -tzf "$CODEX_ASSET" | rg '/\.codex-plugin/plugin\.json$')
GEMINI_MANIFESTS=$(tar -tzf "$GEMINI_ASSET" | rg '/gemini-extension\.json$')
test -n "$CODEX_MANIFESTS"
test -n "$GEMINI_MANIFESTS"
while IFS= read -r manifest; do
  tar -xOzf "$CODEX_ASSET" "$manifest" | jq -e --arg v "$VERSION" '.version == $v' >/dev/null
done <<< "$CODEX_MANIFESTS"
while IFS= read -r manifest; do
  tar -xOzf "$GEMINI_ASSET" "$manifest" | jq -e --arg v "$VERSION" '.version == $v' >/dev/null
done <<< "$GEMINI_MANIFESTS"
```

- [ ] **Step 4: Commit the release bump**

Run:

```bash
git add .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json
git commit -m "chore(release): release v1.7.4"
```

---

### Task 3: Merge and Publish v1.7.4

**Files:**
- No additional repository changes unless review findings require fixes.

**Interfaces:**
- Consumes: approved Task 1 and Task 2 commits.
- Produces: merged PR, exact-main release SHA, v1.7.4 tag, and published release with two verified assets.

- [ ] **Step 1: Push and create the PR**

Run:

```bash
git push -u origin HEAD:refs/heads/fix/codex-cli-detection
gh pr create --base main --head fix/codex-cli-detection \
  --title "fix(install): require Codex executable" \
  --body "$(cat <<'EOF'
## Summary
- require a runnable Codex executable before invoking the Codex installer
- preserve stale ~/.codex state and continue other platform installations
- release the correction as v1.7.4

## Test Plan
- `bash -n scripts/install-all.sh`
- `shellcheck scripts/install-all.sh scripts/test-installation.sh`
- `./scripts/test-installation.sh`
- full repository release gate
- verified Codex and Gemini v1.7.4 archives
EOF
)"
```

- [ ] **Step 2: Require clean CI and review gates, then squash merge**

Run `gh pr checks --watch`, inspect reviews, review requests, comments, and unresolved threads. Address every finding with focused tests and the full gate before merging. Merge only when both gates are clean:

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 3: Detach this worktree at merged main and require exact-commit CI**

Run:

```bash
git fetch origin --prune
git switch --detach origin/main
RELEASE_SHA=$(git rev-parse HEAD)
test "$RELEASE_SHA" = "$(git rev-parse origin/main)"
test "$(jq -r '.metadata.version' .claude-plugin/marketplace.json)" = "1.7.4"
```

Use the same non-empty, stable GitHub check-runs REST loop used for v1.7.3. Require every exact-commit check to be completed with `success`, `neutral`, or `skipped`, and verify remote main remains at `RELEASE_SHA`.

- [ ] **Step 4: Create, verify, and publish the release**

Rebuild from detached merged main, then run:

```bash
VERSION=1.7.4
TAG="v${VERSION}"
CODEX_ASSET="dist/gopher-ai-codex-plugins-v${VERSION}.tar.gz"
GEMINI_ASSET="dist/gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
gh release create "$TAG" --draft --target "$RELEASE_SHA" --title "$TAG" --generate-notes \
  "$CODEX_ASSET" "$GEMINI_ASSET"
```

Verify the draft targets `RELEASE_SHA` and contains exactly both assets, publish through the releases API, and verify the lightweight tag resolves exactly to `RELEASE_SHA`.

---

### Task 4: Install and Verify v1.7.4 on Both Hosts

**Files:**
- Host state only.

**Interfaces:**
- Consumes: published v1.7.4 at merged main.
- Produces: successful exact installer runs and verified platform state locally and on Prometheus.

- [ ] **Step 1: Run and verify the exact installer locally**

Run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
```

Require exit zero, a final summary for Claude Code, Codex CLI, and Gemini CLI, all seven Claude cache roots at 1.7.4, six enabled Codex plugins and cache roots at 1.7.4, and seven Gemini extension manifests at 1.7.4.

- [ ] **Step 2: Snapshot Prometheus stale Codex state before installation**

Run:

```bash
ssh prometheus 'set -eu; test -d "$HOME/.codex"; find "$HOME/.codex" -type f -print0 | sort -z | xargs -0 shasum -a 256 > /tmp/gopher-ai-codex-before.sha256; hostname; command -v codex || true; command -v gemini || true'
```

Expected: host `prometheus`, no Codex or Gemini executable, and a checksum snapshot of existing Codex files.

- [ ] **Step 3: Run the exact installer on Prometheus**

Run:

```bash
ssh prometheus 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"'
```

Require exit zero, the exact stale-state skip warning, no `=== Codex CLI ===` section, no Gemini installation, and `Done! Installed for: Claude Code`.

- [ ] **Step 4: Verify Prometheus state and stale Codex preservation**

Run:

```bash
ssh prometheus 'set -eu; CURRENT_VERSION=1.7.4; for plugin in go-dev go-web go-workflow gopher-guides llm-tools productivity tailwind; do test -d "$HOME/.claude/plugins/cache/gopher-ai/$plugin/$CURRENT_VERSION"; done; test "$(git -C "$HOME/.claude/plugins/marketplaces/gopher-ai" rev-parse HEAD)" = "$(git ls-remote https://github.com/gopherguides/gopher-ai.git refs/tags/v1.7.4 | awk "{print \$1}")"; find "$HOME/.codex" -type f -print0 | sort -z | xargs -0 shasum -a 256 > /tmp/gopher-ai-codex-after.sha256; cmp -s /tmp/gopher-ai-codex-before.sha256 /tmp/gopher-ai-codex-after.sha256'
```

Expected: all Claude plugins at 1.7.4, marketplace checkout at the release SHA, and existing Codex files unchanged.

- [ ] **Step 5: Verify final release and repository state**

Run locally:

```bash
git status --short --branch
gh release view v1.7.4 --json isDraft,tagName,url,targetCommitish,assets \
  --jq '{draft:.isDraft,tag:.tagName,url:.url,target:.targetCommitish,assets:[.assets[].name]}'
```

Expected: clean detached worktree at merged main and published v1.7.4 with exactly both release assets.
