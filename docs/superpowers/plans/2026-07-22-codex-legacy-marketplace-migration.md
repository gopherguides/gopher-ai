# Codex Legacy Marketplace Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Safely migrate the legacy user-local Gopher AI Codex marketplace to the Git-backed marketplace, publish v1.7.3, and verify the public installer locally and on Prometheus.

**Architecture:** `scripts/install-codex.sh` will treat the legacy marketplace as a transaction: prove ownership, move it aside before Codex resolves duplicate marketplace names, restore it on any failure, and retire it only after every plugin installs successfully. Existing cache-root backup behavior remains intact and is rolled back alongside the marketplace file.

**Tech Stack:** Bash 3-compatible shell scripting, `jq`, mocked Codex CLI fixtures, Git/GitHub CLI, shellcheck, existing repository release scripts.

## Global Constraints

- Preserve malformed, mixed, unknown, or user-authored marketplace files without modification.
- Migrate only `~/.agents/plugins/marketplace.json` files named `gopher-ai` whose plugins are all current Codex-capable Gopher AI plugins and whose sources exactly match `./.codex/plugins/<plugin-name>`.
- Restore the legacy marketplace byte-for-byte if marketplace registration, marketplace upgrade, or any plugin installation fails.
- Preserve prior versioned Codex cache roots for active sessions.
- Keep repository-scoped `--repo` behavior unchanged.
- Synchronize every marketplace, Claude plugin, and Codex plugin manifest to 1.7.3.
- Use PR-generated release notes and publish only after exact-main-commit CI succeeds.
- Run the user's exact public installer command on both hosts after v1.7.3 is published.

---

## File Map

- `scripts/install-codex.sh`: Owns legacy marketplace detection, transactional backup, rollback, commit, and Codex user installation.
- `scripts/test-installation.sh`: Extends the Codex CLI stub and covers successful migration, failure rollback, and ownership refusal.
- `.claude-plugin/marketplace.json`: Marketplace metadata and seven plugin version declarations.
- `plugins/go-dev/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/go-dev/.codex-plugin/plugin.json`: Codex plugin version.
- `plugins/go-web/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/go-web/.codex-plugin/plugin.json`: Codex plugin version.
- `plugins/go-workflow/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/go-workflow/.codex-plugin/plugin.json`: Codex plugin version.
- `plugins/gopher-guides/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/gopher-guides/.codex-plugin/plugin.json`: Codex plugin version.
- `plugins/llm-tools/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/llm-tools/.codex-plugin/plugin.json`: Codex plugin version.
- `plugins/productivity/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/tailwind/.claude-plugin/plugin.json`: Claude plugin version.
- `plugins/tailwind/.codex-plugin/plugin.json`: Codex plugin version.

---

### Task 1: Add Transactional Legacy Marketplace Migration

**Files:**
- Modify: `scripts/test-installation.sh:893-1143`
- Modify: `scripts/install-codex.sh:10-12`
- Modify: `scripts/install-codex.sh:56-69`
- Modify: `scripts/install-codex.sh:495-584`

**Interfaces:**
- Consumes: `ROOT_DIR`, `HOME`, current plugin directories containing `.codex-plugin/plugin.json`, `jq`, existing `backup_published_plugin_roots`, and existing `restore_removed_plugin_roots`.
- Produces: `prepare_legacy_user_marketplace_migration()`, `restore_legacy_user_marketplace()`, and `commit_legacy_user_marketplace_migration()` with no arguments and shell status semantics.

- [ ] **Step 1: Extend the Codex stub so duplicate resolution and rollback failures are reproducible**

In `build_stub_path()` inside `scripts/test-installation.sh`, add this branch immediately after the existing marketplace-list branch:

```sh
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "marketplace" ] && [ "${3:-}" = "upgrade" ]; then
  if [ "${CODEX_STUB_FAIL_MARKETPLACE_UPGRADE:-false}" = "true" ]; then
    printf 'forced marketplace upgrade failure\n' >&2
    exit 1
  fi
  exit
fi
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "marketplace" ] && [ "${3:-}" = "add" ]; then
  if [ "${CODEX_STUB_FAIL_MARKETPLACE_ADD:-false}" = "true" ]; then
    printf 'forced marketplace add failure\n' >&2
    exit 1
  fi
  exit
fi
```

Then replace the `plugin add` branch with:

```sh
if [ "${1:-}" = "plugin" ] && [ "${2:-}" = "add" ]; then
  plugin="${3%@*}"
  legacy_marketplace="$HOME/.agents/plugins/marketplace.json"
  if [ -f "$legacy_marketplace" ] && [ "$(jq -r '.name // empty' "$legacy_marketplace")" = "gopher-ai" ]; then
    legacy_path="$(jq -r --arg plugin "$plugin" '.plugins[]? | select(.name == $plugin) | .source.path // empty' "$legacy_marketplace")"
    if [ -n "$legacy_path" ]; then
      resolved_path="$HOME/${legacy_path#./}"
      if [ ! -d "$resolved_path" ]; then
        printf 'plugin source path is not a directory: %s\n' "$resolved_path" >&2
        exit 1
      fi
    fi
  fi
  if [ "${CODEX_STUB_FAIL_ADD_PLUGIN:-}" = "$plugin" ]; then
    printf 'forced plugin add failure: %s\n' "$plugin" >&2
    exit 1
  fi
  source_root="${CODEX_STUB_SOURCE_ROOT:?}/plugins/$plugin"
  version="$(jq -r '.version' "$source_root/.codex-plugin/plugin.json")"
  plugin_cache="$HOME/.codex/plugins/cache/gopher-ai/$plugin"
  destination="$plugin_cache/$version"
  rm -rf "$plugin_cache"
  mkdir -p "$destination"
  cp -R "$source_root"/. "$destination/"
  rm -rf "$destination/.claude-plugin"
  exit
fi
```

- [ ] **Step 2: Add the failing successful-migration regression test**

Insert after the registered marketplace test at `scripts/test-installation.sh:992`:

```sh
echo -n "Codex --user migrates the owned legacy user marketplace... "
LEGACY_MARKETPLACE="$TMP_HOME/.agents/plugins/marketplace.json"
mkdir -p "$(dirname "$LEGACY_MARKETPLACE")"
cp "$ROOT_DIR/dist/codex/plugins/marketplace.json" "$LEGACY_MARKETPLACE"
: > "$STUB_LOG"
if ! HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-legacy-marketplace.log 2>&1; then
  echo "FAIL (--user did not migrate the owned legacy marketplace)"
  sed -n '1,40p' /tmp/gopher-ai-legacy-marketplace.log
  ERRORS=$((ERRORS + 1))
elif [ -e "$LEGACY_MARKETPLACE" ]; then
  echo "FAIL (owned legacy marketplace remained after successful install)"
  ERRORS=$((ERRORS + 1))
elif ! grep -qx 'plugin marketplace upgrade gopher-ai' "$STUB_LOG"; then
  echo "FAIL (Git marketplace was not upgraded after migration)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
```

- [ ] **Step 3: Add failing rollback and ownership-safety tests**

Insert immediately after the successful-migration test:

```sh
echo -n "Codex --user restores the legacy marketplace after plugin failure... "
mkdir -p "$(dirname "$LEGACY_MARKETPLACE")"
cp "$ROOT_DIR/dist/codex/plugins/marketplace.json" "$LEGACY_MARKETPLACE"
LEGACY_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$LEGACY_COPY"
ROLLBACK_ROOT="$TMP_HOME/.codex/plugins/cache/gopher-ai/go-dev/1.7.1"
mkdir -p "$ROLLBACK_ROOT"
echo "active session" > "$ROLLBACK_ROOT/ACTIVE_SESSION"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  CODEX_STUB_FAIL_ADD_PLUGIN=go-web bash "$ROOT_DIR/scripts/install-codex.sh" --user \
  >/tmp/gopher-ai-legacy-rollback.log 2>&1
LEGACY_EXIT=$?
set -e
if [ "$LEGACY_EXIT" -eq 0 ]; then
  echo "FAIL (forced plugin failure unexpectedly succeeded)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$LEGACY_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (legacy marketplace was not restored byte-for-byte)"
  ERRORS=$((ERRORS + 1))
elif [ ! -f "$ROLLBACK_ROOT/ACTIVE_SESSION" ]; then
  echo "FAIL (prior cache root was not restored after plugin failure)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$LEGACY_COPY"

echo -n "Codex --user restores the legacy marketplace after marketplace upgrade failure... "
LEGACY_UPGRADE_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$LEGACY_UPGRADE_COPY"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  CODEX_STUB_FAIL_MARKETPLACE_UPGRADE=true bash "$ROOT_DIR/scripts/install-codex.sh" --user \
  >/tmp/gopher-ai-legacy-upgrade-rollback.log 2>&1
UPGRADE_EXIT=$?
set -e
if [ "$UPGRADE_EXIT" -eq 0 ]; then
  echo "FAIL (forced marketplace upgrade failure unexpectedly succeeded)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$LEGACY_UPGRADE_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (legacy marketplace was not restored after upgrade failure)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$LEGACY_UPGRADE_COPY"

echo -n "Codex --user restores the legacy marketplace after marketplace registration failure... "
LEGACY_ADD_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$LEGACY_ADD_COPY"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_FAIL_MARKETPLACE_ADD=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user \
  >/tmp/gopher-ai-legacy-add-rollback.log 2>&1
ADD_EXIT=$?
set -e
if [ "$ADD_EXIT" -eq 0 ]; then
  echo "FAIL (forced marketplace registration failure unexpectedly succeeded)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$LEGACY_ADD_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (legacy marketplace was not restored after registration failure)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$LEGACY_ADD_COPY"

echo -n "Codex --user preserves and rejects an uncertain gopher-ai marketplace... "
UNKNOWN_COPY=$(mktemp)
jq '.plugins[0].source.path = "./custom/go-dev"' \
  "$ROOT_DIR/dist/codex/plugins/marketplace.json" > "$LEGACY_MARKETPLACE"
cp "$LEGACY_MARKETPLACE" "$UNKNOWN_COPY"
: > "$STUB_LOG"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-legacy-uncertain.log 2>&1
UNCERTAIN_EXIT=$?
set -e
if [ "$UNCERTAIN_EXIT" -eq 0 ]; then
  echo "FAIL (uncertain marketplace unexpectedly migrated)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$UNKNOWN_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (uncertain marketplace was modified)"
  ERRORS=$((ERRORS + 1))
elif grep -q '^plugin marketplace ' "$STUB_LOG"; then
  echo "FAIL (Codex marketplace state changed before ownership was proven)"
  ERRORS=$((ERRORS + 1))
elif ! grep -q 'preserved' /tmp/gopher-ai-legacy-uncertain.log; then
  echo "FAIL (error did not explain that uncertain state was preserved)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$UNKNOWN_COPY"

echo -n "Codex --user preserves and rejects an unknown gopher-ai plugin... "
jq '.plugins += [{"name":"unknown-plugin","source":{"source":"local","path":"./.codex/plugins/unknown-plugin"}}]' \
  "$ROOT_DIR/dist/codex/plugins/marketplace.json" > "$LEGACY_MARKETPLACE"
UNKNOWN_PLUGIN_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$UNKNOWN_PLUGIN_COPY"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-legacy-unknown.log 2>&1
UNKNOWN_PLUGIN_EXIT=$?
set -e
if [ "$UNKNOWN_PLUGIN_EXIT" -eq 0 ]; then
  echo "FAIL (unknown plugin marketplace unexpectedly migrated)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$UNKNOWN_PLUGIN_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (unknown plugin marketplace was modified)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$UNKNOWN_PLUGIN_COPY"

echo -n "Codex --user preserves and rejects a malformed marketplace... "
printf '{invalid json\n' > "$LEGACY_MARKETPLACE"
MALFORMED_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$MALFORMED_COPY"
set +e
HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user >/tmp/gopher-ai-legacy-malformed.log 2>&1
MALFORMED_EXIT=$?
set -e
if [ "$MALFORMED_EXIT" -eq 0 ]; then
  echo "FAIL (malformed marketplace unexpectedly migrated)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$MALFORMED_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (malformed marketplace was modified)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$MALFORMED_COPY"

echo -n "Codex --user leaves an unrelated user marketplace untouched... "
jq '.name = "other-marketplace"' "$ROOT_DIR/dist/codex/plugins/marketplace.json" > "$LEGACY_MARKETPLACE"
UNRELATED_COPY=$(mktemp)
cp "$LEGACY_MARKETPLACE" "$UNRELATED_COPY"
if ! HOME="$TMP_HOME" PATH="$STUB_PATH" CODEX_STUB_LOG="$STUB_LOG" \
  CODEX_STUB_SOURCE_ROOT="$ROOT_DIR" CODEX_STUB_MARKETPLACE_REGISTERED=true \
  bash "$ROOT_DIR/scripts/install-codex.sh" --user >/dev/null 2>&1; then
  echo "FAIL (unrelated marketplace blocked installation)"
  ERRORS=$((ERRORS + 1))
elif ! cmp -s "$UNRELATED_COPY" "$LEGACY_MARKETPLACE"; then
  echo "FAIL (unrelated marketplace was modified)"
  ERRORS=$((ERRORS + 1))
else
  echo "OK"
fi
rm -f "$UNRELATED_COPY" "$LEGACY_MARKETPLACE"
```

- [ ] **Step 4: Run the installation tests and verify the migration tests fail for the expected reason**

Run:

```bash
./scripts/test-installation.sh
```

Expected: the new successful-migration test fails with `plugin source path is not a directory`, while the existing tests continue running and no syntax error occurs.

- [ ] **Step 5: Add transaction state and make the exit trap restore an uncommitted marketplace**

Add near `CACHE_BACKUP_DIRS=()` in `scripts/install-codex.sh`:

```bash
LEGACY_MARKETPLACE_PATH=""
LEGACY_MARKETPLACE_BACKUP_DIR=""
```

Add before `cleanup()`:

```bash
restore_legacy_user_marketplace() {
    [[ -n "$LEGACY_MARKETPLACE_PATH" ]] || return 0
    local backup_file="$LEGACY_MARKETPLACE_BACKUP_DIR/marketplace.json"
    if [[ -e "$backup_file" || -L "$backup_file" ]]; then
        mkdir -p "$(dirname "$LEGACY_MARKETPLACE_PATH")"
        mv "$backup_file" "$LEGACY_MARKETPLACE_PATH"
    fi
    [[ -z "$LEGACY_MARKETPLACE_BACKUP_DIR" ]] || rm -rf "$LEGACY_MARKETPLACE_BACKUP_DIR"
    LEGACY_MARKETPLACE_PATH=""
    LEGACY_MARKETPLACE_BACKUP_DIR=""
}
```

Make `cleanup()` call `restore_legacy_user_marketplace` before removing bootstrap and cache backup directories:

```bash
cleanup() {
    restore_legacy_user_marketplace
    if [[ -n "$BOOTSTRAP_DIR" && -d "$BOOTSTRAP_DIR" ]]; then
        rm -rf "$BOOTSTRAP_DIR"
    fi
    local cache_backup_dir
    for cache_backup_dir in "${CACHE_BACKUP_DIRS[@]-}"; do
        [[ -n "$cache_backup_dir" ]] || continue
        if [[ -d "$cache_backup_dir" ]]; then
            rm -rf "$cache_backup_dir"
        fi
    done
}
```

- [ ] **Step 6: Implement strict ownership detection, preparation, and commit**

Add before `install_user_plugins()`:

```bash
codex_plugin_names_json() {
    local plugin_dir
    for plugin_dir in "$ROOT_DIR"/plugins/*; do
        [[ -d "$plugin_dir" ]] || continue
        [[ -f "$plugin_dir/.codex-plugin/plugin.json" ]] || continue
        basename "$plugin_dir"
    done | jq -R . | jq -s .
}

prepare_legacy_user_marketplace_migration() {
    local candidate="$HOME/.agents/plugins/marketplace.json"
    [[ -e "$candidate" || -L "$candidate" ]] || return 0

    if ! jq -e . "$candidate" >/dev/null 2>&1; then
        echo "error: preserved invalid marketplace file: $candidate" >&2
        echo "       move or repair it before installing gopher-ai." >&2
        return 1
    fi

    local marketplace_name
    marketplace_name="$(jq -r '.name // empty' "$candidate")"
    [[ "$marketplace_name" == "gopher-ai" ]] || return 0

    local allowed_plugins
    allowed_plugins="$(codex_plugin_names_json)"
    if ! jq -e --argjson allowed "$allowed_plugins" '
        (.plugins | type == "array" and length > 0) and
        all(.plugins[];
            (.name | type == "string") and
            ($allowed | index(.name) != null) and
            .source.source == "local" and
            .source.path == ("./.codex/plugins/" + .name)
        )
    ' "$candidate" >/dev/null; then
        echo "error: preserved marketplace because ownership could not be proven: $candidate" >&2
        echo "       remove or rename the conflicting gopher-ai marketplace, then retry." >&2
        return 1
    fi

    local temp_base="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
    LEGACY_MARKETPLACE_BACKUP_DIR="$(mktemp -d "${temp_base%/}/gopher-ai-codex-marketplace.XXXXXX")"
    LEGACY_MARKETPLACE_PATH="$candidate"
    mv "$candidate" "$LEGACY_MARKETPLACE_BACKUP_DIR/marketplace.json"
    echo "migrating legacy Codex marketplace: $candidate"
}

commit_legacy_user_marketplace_migration() {
    [[ -z "$LEGACY_MARKETPLACE_BACKUP_DIR" ]] || rm -rf "$LEGACY_MARKETPLACE_BACKUP_DIR"
    LEGACY_MARKETPLACE_PATH=""
    LEGACY_MARKETPLACE_BACKUP_DIR=""
}
```

- [ ] **Step 7: Integrate the transaction into `install_user_plugins()`**

After the `codex plugin add --help` capability check and before `codex plugin marketplace list --json`, add:

```bash
    prepare_legacy_user_marketplace_migration
```

After all plugin additions and `restore_removed_plugin_roots "$cache_backup_dir"` succeed, add:

```bash
    commit_legacy_user_marketplace_migration
```

Do not add marketplace restore calls to individual error branches; returning non-zero must flow through the existing `EXIT` trap, which restores the uncommitted marketplace exactly once.

- [ ] **Step 8: Run focused verification**

Run:

```bash
bash -n scripts/install-codex.sh
shellcheck scripts/install-codex.sh scripts/test-installation.sh
./scripts/test-installation.sh
```

Expected: all commands exit zero and the new tests print `OK` for migration, rollback, uncertain ownership, and unrelated marketplace preservation.

- [ ] **Step 9: Commit the migration fix**

Run:

```bash
git add scripts/install-codex.sh scripts/test-installation.sh
git commit -m "fix(codex): migrate legacy marketplace"
```

Expected: one focused fix commit on `fix/codex-legacy-marketplace-migration`.

---

### Task 2: Bump v1.7.3 and Run the Release Gate

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/go-dev/.claude-plugin/plugin.json`
- Modify: `plugins/go-dev/.codex-plugin/plugin.json`
- Modify: `plugins/go-web/.claude-plugin/plugin.json`
- Modify: `plugins/go-web/.codex-plugin/plugin.json`
- Modify: `plugins/go-workflow/.claude-plugin/plugin.json`
- Modify: `plugins/go-workflow/.codex-plugin/plugin.json`
- Modify: `plugins/gopher-guides/.claude-plugin/plugin.json`
- Modify: `plugins/gopher-guides/.codex-plugin/plugin.json`
- Modify: `plugins/llm-tools/.claude-plugin/plugin.json`
- Modify: `plugins/llm-tools/.codex-plugin/plugin.json`
- Modify: `plugins/productivity/.claude-plugin/plugin.json`
- Modify: `plugins/tailwind/.claude-plugin/plugin.json`
- Modify: `plugins/tailwind/.codex-plugin/plugin.json`

**Interfaces:**
- Consumes: the migration fix from Task 1 and the release workflow's manifest synchronization requirement.
- Produces: all version sources set to `1.7.3` and verified release archives in `dist/`.

- [ ] **Step 1: Update every version source to 1.7.3**

Run:

```bash
VERSION=1.7.3
jq --arg v "$VERSION" '.metadata.version = $v | .plugins[].version = $v' \
  .claude-plugin/marketplace.json > /tmp/marketplace.json.tmp
mv /tmp/marketplace.json.tmp .claude-plugin/marketplace.json
for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
  [ -f "$pjson" ] || continue
  jq --arg v "$VERSION" '.version = $v' "$pjson" > /tmp/plugin.json.tmp
  mv /tmp/plugin.json.tmp "$pjson"
done
```

- [ ] **Step 2: Verify every manifest reports 1.7.3**

Run:

```bash
VERSION=1.7.3
jq -e --arg v "$VERSION" '.metadata.version == $v and all(.plugins[]; .version == $v)' \
  .claude-plugin/marketplace.json >/dev/null
for pjson in plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json; do
  [ -f "$pjson" ] || continue
  jq -e --arg v "$VERSION" '.version == $v' "$pjson" >/dev/null
done
! rg -n '"version": "1\.7\.2"' .claude-plugin/marketplace.json \
  plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json
```

Expected: all commands exit zero and the final search prints nothing.

- [ ] **Step 3: Run the full repository gate**

Run:

```bash
bash -lc './scripts/test-installation.sh && ./scripts/test-commands.sh && ./scripts/test-hooks.sh && ./scripts/test-ship-e2e-gate.sh && ./scripts/check-shared-sync.sh && shellcheck agent-skills/scripts/*.sh && for skill_dir in agent-skills/skills/*/; do skill_name=$(basename "$skill_dir"); skill_file="$skill_dir/SKILL.md"; test -f "$skill_file"; lines=$(wc -l < "$skill_file"); test "$lines" -lt 500; name=$(sed -n "/^---$/,/^---$/p" "$skill_file" | awk "/^name:/ {print \$2; exit}"); test "$name" = "$skill_name"; rg -q "^description:" "$skill_file"; done && ruby -ryaml -e "YAML.load_file(ARGV[0])" agent-skills/config/severity.yaml && (cd agent-skills/examples/demo-repo && go build -o /tmp/gopher-ai-demo . && go test ./...)'
```

Expected: every test suite passes, shared files are synchronized, shellcheck succeeds, and the demo Go build/tests pass.

- [ ] **Step 4: Build and verify v1.7.3 archives**

Run:

```bash
./scripts/build-universal.sh
VERSION=1.7.3
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

Expected: both archives exist and every packaged manifest reports 1.7.3.

- [ ] **Step 5: Commit the release version**

Run:

```bash
git add .claude-plugin/marketplace.json plugins/*/.claude-plugin/plugin.json plugins/*/.codex-plugin/plugin.json
git commit -m "chore(release): release v1.7.3"
```

Expected: the release bump is separate from the migration fix.

---

### Task 3: Merge the Fix and Publish v1.7.3

**Files:**
- No additional repository files.

**Interfaces:**
- Consumes: the tested branch commits and verified archives from Tasks 1-2.
- Produces: merged `main`, tag `v1.7.3`, published GitHub release, and two release assets tied to the exact CI-verified main commit.

- [ ] **Step 1: Verify branch state and push**

Run:

```bash
git status --short --branch
test -z "$(git status --porcelain)"
git push -u origin fix/codex-legacy-marketplace-migration
```

Expected: clean branch and successful push.

- [ ] **Step 2: Create the pull request**

No PR template exists, so run:

```bash
gh pr create --base main --head fix/codex-legacy-marketplace-migration \
  --title "fix(codex): migrate legacy marketplace" \
  --body "$(cat <<'EOF'
## Summary
- migrate the installer-owned legacy Codex marketplace before Git marketplace resolution
- restore legacy marketplace and cache state after failed installs
- release the correction as v1.7.3

## Test Plan
- `bash -n scripts/install-codex.sh`
- `shellcheck scripts/install-codex.sh scripts/test-installation.sh`
- `./scripts/test-installation.sh`
- full repository release gate
- verified Codex and Gemini v1.7.3 archives
EOF
)"
```

Expected: GitHub returns the new PR URL.

- [ ] **Step 3: Wait for CI and reviews, address every finding, and merge**

Run:

```bash
gh pr checks --watch
PR_NUMBER=$(gh pr view --json number --jq '.number')
gh pr reviews "$PR_NUMBER" --json author,state,body
gh pr view "$PR_NUMBER" --json reviewRequests
```

Expected: all checks pass, no `CHANGES_REQUESTED`, `COMMENTED`, or pending bot review remains. If any review finding exists, fix it immediately, rerun the affected tests and full gate, commit, push, and repeat the checks/review gate before merging.

Merge with:

```bash
gh pr merge "$PR_NUMBER" --squash --delete-branch
```

Expected: PR is merged and the remote feature branch is deleted.

- [ ] **Step 4: Update local main and identify the exact release commit**

Run:

```bash
git switch main
git pull --ff-only origin main
RELEASE_SHA=$(git rev-parse HEAD)
test "$RELEASE_SHA" = "$(git rev-parse origin/main)"
test "$(jq -r '.metadata.version' .claude-plugin/marketplace.json)" = "1.7.3"
printf 'RELEASE_SHA=%s\n' "$RELEASE_SHA"
```

Expected: local and remote main match and the manifest is 1.7.3.

- [ ] **Step 5: Require exact release-commit CI success**

Run the release workflow's REST check loop against `$RELEASE_SHA`:

```bash
CHECKS=""
for attempt in $(seq 1 24); do
  CHECKS=$(gh api "repos/gopherguides/gopher-ai/commits/${RELEASE_SHA}/check-runs")
  [ "$(jq '.total_count' <<< "$CHECKS")" -gt 0 ] && break
  sleep 5
done
test "$(jq '.total_count' <<< "$CHECKS")" -gt 0
for attempt in $(seq 1 60); do
  CHECKS=$(gh api "repos/gopherguides/gopher-ai/commits/${RELEASE_SHA}/check-runs")
  FAILED=$(jq '[.check_runs[] | select(.status == "completed" and (.conclusion | IN("success", "neutral", "skipped") | not))] | length' <<< "$CHECKS")
  PENDING=$(jq '[.check_runs[] | select(.status != "completed")] | length' <<< "$CHECKS")
  test "$FAILED" -eq 0
  [ "$PENDING" -eq 0 ] && break
  sleep 10
done
GREEN_COUNT=$(jq '.total_count' <<< "$CHECKS")
sleep 10
CHECKS=$(gh api "repos/gopherguides/gopher-ai/commits/${RELEASE_SHA}/check-runs")
test "$(jq '[.check_runs[] | select(.status != "completed")] | length' <<< "$CHECKS")" -eq 0
test "$(jq '[.check_runs[] | select(.conclusion | IN("success", "neutral", "skipped") | not)] | length' <<< "$CHECKS")" -eq 0
test "$(jq '.total_count' <<< "$CHECKS")" -eq "$GREEN_COUNT"
test "$(git rev-parse HEAD)" = "$RELEASE_SHA"
test "$(git ls-remote origin refs/heads/main | awk '{print $1}')" = "$RELEASE_SHA"
```

Expected: a non-empty stable check set, all completed successfully, and main unchanged.

- [ ] **Step 6: Rebuild assets from merged main and create a verified draft**

Run:

```bash
./scripts/build-universal.sh
VERSION=1.7.3
TAG="v${VERSION}"
CODEX_ASSET="dist/gopher-ai-codex-plugins-v${VERSION}.tar.gz"
GEMINI_ASSET="dist/gopher-ai-gemini-extensions-v${VERSION}.tar.gz"
gh release create "$TAG" --draft --target "$RELEASE_SHA" --title "$TAG" --generate-notes \
  "$CODEX_ASSET" "$GEMINI_ASSET"
RELEASE=$(gh api --paginate --slurp repos/gopherguides/gopher-ai/releases \
  | jq --arg tag "$TAG" 'add | map(select(.tag_name == $tag)) | first')
test "$(jq -r '.draft' <<< "$RELEASE")" = "true"
test "$(jq -r '.target_commitish' <<< "$RELEASE")" = "$RELEASE_SHA"
jq -e --arg codex "${CODEX_ASSET##*/}" --arg gemini "${GEMINI_ASSET##*/}" '
  (.assets | length) == 2 and
  ([.assets[].name] | sort) == ([$codex, $gemini] | sort)
' <<< "$RELEASE" >/dev/null
RELEASE_ID=$(jq -r '.id' <<< "$RELEASE")
```

Expected: draft v1.7.3 targets the exact verified commit and contains exactly the Codex and Gemini archives.

- [ ] **Step 7: Publish and verify v1.7.3**

Run:

```bash
gh api --method PATCH "repos/gopherguides/gopher-ai/releases/${RELEASE_ID}" -F draft=false >/dev/null
PUBLISHED=$(gh api "repos/gopherguides/gopher-ai/releases/${RELEASE_ID}")
jq -e --arg tag "$TAG" --arg codex "${CODEX_ASSET##*/}" --arg gemini "${GEMINI_ASSET##*/}" '
  (.draft | not) and .tag_name == $tag and
  ([.assets[].name] | sort) == ([$codex, $gemini] | sort)
' <<< "$PUBLISHED" >/dev/null
test "$(gh api "repos/gopherguides/gopher-ai/git/ref/tags/${TAG}" --jq '.object.sha')" = "$RELEASE_SHA"
jq '{draft,tag_name,html_url,assets:[.assets[].name]}' <<< "$PUBLISHED"
```

Expected: published release URL, tag v1.7.3 at `$RELEASE_SHA`, and exactly two assets.

---

### Task 4: Install and Verify v1.7.3 on Both Hosts

**Files:**
- Host state only; no repository file changes.

**Interfaces:**
- Consumes: published v1.7.3 on `main` and the public raw GitHub installer URL.
- Produces: successful Claude Code, Codex, and Gemini installation on this machine and Prometheus.

- [ ] **Step 1: Run the exact installer locally**

Run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"
```

Expected: exit zero, Claude Code refresh reports 1.7.3, Codex installs six plugins through the CLI, Gemini installs seven extensions, and the final `Done!` summary appears.

- [ ] **Step 2: Verify local Codex migration and versions**

Run:

```bash
test ! -e "$HOME/.agents/plugins/marketplace.json"
CURRENT_VERSION=1.7.3
CODEX_JSON=$(codex plugin list --json)
jq -e --arg v "$CURRENT_VERSION" '
  [.installed[] | select(.marketplaceName == "gopher-ai")] as $plugins |
  ($plugins | length) == 6 and
  all($plugins[]; .installed and .enabled and .version == $v)
' <<< "$CODEX_JSON" >/dev/null
for plugin in go-dev go-web go-workflow gopher-guides llm-tools tailwind; do
  test -f "$HOME/.codex/plugins/cache/gopher-ai/$plugin/$CURRENT_VERSION/.codex-plugin/plugin.json"
done
for plugin in go-dev go-web go-workflow gopher-guides llm-tools productivity tailwind; do
  test -d "$HOME/.claude/plugins/cache/gopher-ai/$plugin/$CURRENT_VERSION"
done
```

Expected: no legacy marketplace, six enabled Codex plugins at 1.7.3, complete Codex cache roots, and seven Claude Code cache roots.

- [ ] **Step 3: Confirm Prometheus connectivity and platform tools**

Run:

```bash
ssh prometheus 'hostname; command -v bash; command -v curl; command -v jq; command -v codex || true; command -v gemini || true; test -d "$HOME/.claude" && echo claude-home-present || true'
```

Expected: SSH succeeds and the host reports the installed platform tools before mutation.

- [ ] **Step 4: Run the exact installer on Prometheus**

Run:

```bash
ssh prometheus 'bash -c "$(curl -fsSL https://raw.githubusercontent.com/gopherguides/gopher-ai/main/scripts/install-all.sh)"'
```

Expected: exit zero and the final installer summary lists every platform detected on Prometheus.

- [ ] **Step 5: Verify Prometheus Codex and Claude versions when those platforms are present**

Run:

```bash
ssh prometheus '
set -eu
CURRENT_VERSION=1.7.3
if command -v codex >/dev/null 2>&1; then
  test ! -e "$HOME/.agents/plugins/marketplace.json"
  CODEX_JSON=$(codex plugin list --json)
  jq -e --arg v "$CURRENT_VERSION" '\''
    [.installed[] | select(.marketplaceName == "gopher-ai")] as $plugins |
    ($plugins | length) == 6 and
    all($plugins[]; .installed and .enabled and .version == $v)
  '\'' <<EOF >/dev/null
$CODEX_JSON
EOF
fi
if [ -d "$HOME/.claude/plugins/cache/gopher-ai" ]; then
  for plugin in go-dev go-web go-workflow gopher-guides llm-tools productivity tailwind; do
    test -d "$HOME/.claude/plugins/cache/gopher-ai/$plugin/$CURRENT_VERSION"
  done
fi
'
```

Expected: every detected platform verifies at 1.7.3 and no legacy Codex marketplace remains.

- [ ] **Step 6: Final repository and release verification**

Run locally:

```bash
git status --short --branch
gh release view v1.7.3 --json isDraft,tagName,url,targetCommitish,assets \
  --jq '{draft:.isDraft,tag:.tagName,url,target:.targetCommitish,assets:[.assets[].name]}'
```

Expected: clean `main`, published v1.7.3, exact target commit, and both expected assets.
