#!/bin/bash
# regen-legacy-hashes.sh — Regenerate scripts/legacy-skill-hashes.txt from git history.
#
# The manifest is a sorted list of sha256 hashes covering every version of every
# `plugins/*/skills/*/SKILL.md` blob that has shipped on the default branch,
# plus the final skill contents of the current change. The
# Codex `--cleanup` migration uses it to verify ownership of files left over
# in `~/.codex/skills/` from the old `--user` install path — without needing
# git history at install time (the curl one-liner unpacks a tarball).
#
# Run this whenever new SKILL.md content is ready to ship.
# CI's check-installation could also enforce that the manifest is in sync.
#
# Usage:
#   scripts/regen-legacy-hashes.sh [--check] [--base-ref <ref>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST="$ROOT_DIR/scripts/legacy-skill-hashes.txt"
# The hook ships its own copy because Claude Code installs the plugin to a
# cache directory without the repo's scripts/. Both files are the source of
# truth, kept identical by this regen.
HOOK_MANIFEST="$ROOT_DIR/plugins/go-workflow/hooks/legacy-skill-hashes.txt"

CHECK_ONLY=false
BASE_REF=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            CHECK_ONLY=true
            shift
            ;;
        --base-ref)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "error: --base-ref requires a Git ref" >&2
                exit 1
            fi
            BASE_REF="$2"
            shift 2
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

cd "$ROOT_DIR"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: scripts/regen-legacy-hashes.sh must be run from a git clone" >&2
    exit 1
fi

# Refuse to run on a shallow clone — it would silently produce a manifest
# missing historical SKILL.md hashes that are precisely what the migration
# needs. CI runners (e.g. actions/checkout@v4) default to shallow.
if [[ "$(git rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
    cat >&2 <<'EOF'
error: this is a shallow git clone. The manifest must be built from the FULL
history because its purpose is to recognize OLD shipped versions of SKILL.md
files left in users' ~/.codex/skills/. A shallow regen would write a partial
manifest that silently fails to migrate older --user installs.

Fix: fetch full history first, then re-run.

  git fetch --unshallow

(In CI: set fetch-depth: 0 on actions/checkout.)
EOF
    exit 1
fi

if [[ -z "$BASE_REF" && -n "${GITHUB_BASE_REF:-}" ]] &&
    git rev-parse --verify --quiet "refs/remotes/origin/${GITHUB_BASE_REF}^{commit}" >/dev/null; then
    BASE_REF="refs/remotes/origin/${GITHUB_BASE_REF}"
fi

if [[ -z "$BASE_REF" ]]; then
    current_branch="$(git branch --show-current)"
    default_remote_ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    default_branch="${default_remote_ref#origin/}"
    if [[ -n "$current_branch" && -n "$default_remote_ref" && "$current_branch" != "$default_branch" ]]; then
        BASE_REF="$default_remote_ref"
    else
        BASE_REF="HEAD"
    fi
fi

if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
    echo "error: base ref '$BASE_REF' does not resolve to a commit" >&2
    exit 1
fi

# Collect every blob OID that has ever existed in this branch history at a path
# matching plugins/<plugin>/skills/<skill>/SKILL.md, then emit
# <sha256> <skill_name> pairs. The skill name is necessary to preserve
# per-skill ownership during manifest-based cleanup — a hash that originated
# from skill A must not be accepted as proof of ownership for a candidate in
# directory B.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

{
    git rev-list --objects "$BASE_REF" 2>/dev/null \
        | awk '$2 ~ "^plugins/[^/]+/skills/[^/]+/SKILL[.]md$" {print $1, $2}' \
        | while read -r blob path; do
            skill_name="$(basename "$(dirname "$path")")"
            hash="$(git cat-file blob "$blob" 2>/dev/null | sha256sum | awk '{print $1}')"
            [[ -n "$hash" ]] && echo "$hash $skill_name"
        done

    for skill_file in "$ROOT_DIR"/plugins/*/skills/*/SKILL.md; do
        [[ -f "$skill_file" ]] || continue
        skill_name="$(basename "$(dirname "$skill_file")")"
        hash="$(sha256sum "$skill_file" | awk '{print $1}')"
        [[ -n "$hash" ]] && echo "$hash $skill_name"
    done
} | sort -u >"$TMP"

count="$(wc -l < "$TMP" | tr -d ' ')"

if [[ "$CHECK_ONLY" == "true" ]]; then
    check_failed=false
    for manifest in "$MANIFEST" "$HOOK_MANIFEST"; do
        if [[ ! -f "$manifest" ]]; then
            echo "error: manifest missing: $manifest" >&2
            check_failed=true
            continue
        fi

        missing="$(comm -23 "$TMP" <(awk '/^[[:space:]]*#/{next} /^[[:space:]]*$/{next} {print}' "$manifest" | sort -u))"
        extra="$(comm -13 "$TMP" <(awk '/^[[:space:]]*#/{next} /^[[:space:]]*$/{next} {print}' "$manifest" | sort -u))"
        if [[ -n "$missing" || -n "$extra" ]]; then
            echo "error: $manifest does not match squash-merge history from $BASE_REF" >&2
            [[ -z "$missing" ]] || printf '  missing %s pair(s)\n' "$(wc -l <<< "$missing" | tr -d ' ')" >&2
            if [[ -n "$extra" ]]; then
                printf '  extra %s pair(s) not in squash-merge history:\n' "$(wc -l <<< "$extra" | tr -d ' ')" >&2
                head -3 <<< "$extra" | sed 's/^/    /' >&2
            fi
            check_failed=true
        fi
    done

    if [[ "$check_failed" == "true" ]]; then
        exit 1
    fi

    echo "legacy skill hash manifests match squash-merge history from $BASE_REF ($count pairs)"
    exit 0
fi

cat > "$MANIFEST" <<EOF
# legacy-skill-hashes.txt — manifest of every gopher-ai SKILL.md blob version
# this repo has ever shipped. Each non-comment line is "<sha256> <skill_name>".
# Regenerated by scripts/regen-legacy-hashes.sh.
# Used by scripts/install-codex.sh --cleanup to safely identify legacy gopher-ai
# installs in ~/.codex/skills/ when running without git history (curl one-liner).
# Both fields must match for cleanup to consider a candidate gopher-ai-owned —
# this prevents accepting a hash from skill A as proof of ownership for skill B.
# DO NOT EDIT BY HAND — re-run the regen script after finalizing SKILL.md changes.
#
# Total entries: $count
EOF
cat "$TMP" >> "$MANIFEST"

# Mirror to the plugin so the SessionStart hook can read it without depending
# on the repo's scripts/ directory.
mkdir -p "$(dirname "$HOOK_MANIFEST")"
cp "$MANIFEST" "$HOOK_MANIFEST"

echo "regenerated: $MANIFEST ($count unique <hash skill_name> pairs from $BASE_REF plus current skills)"
echo "mirrored to: $HOOK_MANIFEST"
