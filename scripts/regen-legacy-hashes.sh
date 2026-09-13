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
LOCK_DIR="$ROOT_DIR/scripts/.regen-legacy-hashes.lock"
TRANSACTION_FILE="$ROOT_DIR/scripts/.legacy-skill-hashes.transaction"
LOCK_FILE=""

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

GIT_DIR="$(git rev-parse --absolute-git-dir)"
LOCK_FILE="$GIT_DIR/gopher-ai-regen-legacy-hashes.lock"

# Refuse to run on a shallow clone — it would silently produce a manifest
# missing historical SKILL.md hashes that are precisely what the migration
# needs. CI runners (e.g. actions/checkout@v7) default to shallow.
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

TEMP_BASE="${TMPDIR:-${TMP:-${TEMP:-/tmp}}}"
TEMP_BASE="${TEMP_BASE%/}"
TMP=""
CANDIDATE=""
STAGED_MANIFEST=""
STAGED_HOOK_MANIFEST=""
STAGED_TRANSACTION=""
LOCK_GUARD_PID=""
LOCK_STATE_DIR=""
COLLECTION_PID=""

cleanup() {
    status=$?
    trap - EXIT INT TERM HUP
    if [[ -n "$COLLECTION_PID" ]]; then
        # Monitor mode gives this worker its own process group. Signal the
        # whole group so a hung git/awk/sort descendant cannot survive its
        # canceled writer. Fall back to the leader if group signaling races
        # with startup.
        kill -TERM -- "-$COLLECTION_PID" 2>/dev/null ||
            kill "$COLLECTION_PID" 2>/dev/null || true
    fi
    [[ -z "$TMP" ]] || rm -f "$TMP"
    [[ -z "$CANDIDATE" ]] || rm -f "$CANDIDATE"
    [[ -z "$STAGED_MANIFEST" ]] || rm -f "$STAGED_MANIFEST"
    [[ -z "$STAGED_HOOK_MANIFEST" ]] || rm -f "$STAGED_HOOK_MANIFEST"
    [[ -z "$STAGED_TRANSACTION" ]] || rm -f "$STAGED_TRANSACTION"
    if [[ -n "$LOCK_GUARD_PID" ]]; then
        kill "$LOCK_GUARD_PID" 2>/dev/null || true
        wait "$LOCK_GUARD_PID" 2>/dev/null || true
    fi
    [[ -z "$LOCK_STATE_DIR" ]] || rm -rf "$LOCK_STATE_DIR"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

acquire_lock() {
    local backend=""
    local lock_ready=""
    local lock_error=""

    LOCK_STATE_DIR=$(/usr/bin/mktemp -d "$TEMP_BASE/gopher-ai-legacy-lock.XXXXXX")
    lock_ready="$LOCK_STATE_DIR/ready"
    lock_error="$LOCK_STATE_DIR/error"

    if command -v perl >/dev/null 2>&1; then
        backend=perl
    elif command -v python3 >/dev/null 2>&1; then
        backend=python3
    else
        echo "error: publication locking requires perl or python3" >&2
        return 1
    fi

    case "$backend" in
        perl)
            perl -MFcntl=:flock -e '
                my ($path, $ready) = @ARGV;
                open(my $lock, ">>", $path) or die "open lock: $!";
                my $parent = getppid();
                until (flock($lock, LOCK_EX | LOCK_NB)) {
                    exit 2 if getppid() != $parent;
                    select(undef, undef, undef, 0.1);
                }
                open(my $signal, ">", $ready) or die "write ready: $!";
                close($signal) or die "close ready: $!";
                while (getppid() == $parent) {
                    select(undef, undef, undef, 0.1);
                }
            ' "$LOCK_FILE" "$lock_ready" 2> "$lock_error" &
            ;;
        python3)
            python3 -c '
import fcntl, os, sys, time
path, ready = sys.argv[1:]
parent = os.getppid()
with open(path, "a") as lock:
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if os.getppid() != parent:
                raise SystemExit(2)
            time.sleep(0.1)
    open(ready, "w").close()
    while os.getppid() == parent:
        time.sleep(0.1)
            ' "$LOCK_FILE" "$lock_ready" 2> "$lock_error" &
            ;;
    esac
    LOCK_GUARD_PID=$!

    while [[ ! -e "$lock_ready" ]]; do
        if ! kill -0 "$LOCK_GUARD_PID" 2>/dev/null; then
            wait "$LOCK_GUARD_PID" 2>/dev/null || true
            echo "error: failed to acquire legacy hash publication lock" >&2
            [[ ! -s "$lock_error" ]] || sed -n '1,5p' "$lock_error" >&2
            return 1
        fi
        if [[ -n "${GOPHER_AI_REGEN_TEST_LOCK_WAIT_FILE:-}" ]]; then
            touch "$GOPHER_AI_REGEN_TEST_LOCK_WAIT_FILE"
        fi
        sleep 0.1
    done
    # Deterministic synchronization point used only by the concurrency test.
    if [[ -n "${GOPHER_AI_REGEN_TEST_HOLD_LOCK:-}" ]]; then
        touch "${GOPHER_AI_REGEN_TEST_HOLD_LOCK}.ready"
        while [[ ! -e "$GOPHER_AI_REGEN_TEST_HOLD_LOCK" ]]; do
            sleep 0.05
        done
    fi
}

remove_legacy_lock_dir() {
    local owner_pid=""

    [[ -d "$LOCK_DIR" ]] || return 0
    if [[ -r "$LOCK_DIR/pid" ]]; then
        read -r owner_pid < "$LOCK_DIR/pid" || owner_pid=""
    fi
    if [[ "$owner_pid" =~ ^[0-9]+$ ]] && kill -0 "$owner_pid" 2>/dev/null; then
        echo "error: legacy publication lock may still be owned by PID $owner_pid" >&2
        return 1
    fi
    rm -rf "$LOCK_DIR"
}

hash_file() {
    sha256sum "$1" | awk '{print $1}'
}

stage_recovery_copy() {
    local source="$1"
    local destination="$2"
    local expected_hash="$3"
    local staged

    staged=$(/usr/bin/mktemp "$(dirname "$destination")/.legacy-skill-hashes.recovery.XXXXXX")
    cp "$source" "$staged"
    chmod 0644 "$staged"
    if [[ "$(hash_file "$staged")" != "$expected_hash" ]]; then
        rm -f "$staged"
        echo "error: recovered manifest failed transaction hash validation" >&2
        return 1
    fi
    mv "$staged" "$destination"
}

recover_interrupted_publication() {
    local expected_hash=""
    local extra=""
    local manifest_hash=""
    local hook_hash=""

    [[ -f "$TRANSACTION_FILE" ]] || return 0
    if ! read -r expected_hash extra < "$TRANSACTION_FILE" ||
       [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ -n "$extra" ]]; then
        echo "error: invalid legacy hash publication transaction marker: $TRANSACTION_FILE" >&2
        return 1
    fi

    [[ ! -f "$MANIFEST" ]] || manifest_hash="$(hash_file "$MANIFEST")"
    [[ ! -f "$HOOK_MANIFEST" ]] || hook_hash="$(hash_file "$HOOK_MANIFEST")"

    if [[ "$manifest_hash" == "$expected_hash" && "$hook_hash" == "$expected_hash" ]]; then
        : # Both renames landed; only marker cleanup was interrupted.
    elif [[ "$manifest_hash" == "$expected_hash" ]]; then
        stage_recovery_copy "$MANIFEST" "$HOOK_MANIFEST" "$expected_hash"
    elif [[ "$hook_hash" == "$expected_hash" ]]; then
        stage_recovery_copy "$HOOK_MANIFEST" "$MANIFEST" "$expected_hash"
    elif [[ -f "$MANIFEST" && -f "$HOOK_MANIFEST" ]] && cmp -s "$MANIFEST" "$HOOK_MANIFEST"; then
        : # The marker landed but publication had not started.
    else
        echo "error: interrupted legacy hash publication cannot be recovered automatically" >&2
        echo "error: neither manifest matches transaction digest $expected_hash" >&2
        return 1
    fi

    rm -f "$TRANSACTION_FILE"
    echo "recovered interrupted legacy hash manifest publication" >&2
}

remove_abandoned_staging_files() {
    # The lock proves no live writer owns these same-checkout staging paths.
    # A SIGKILL can bypass EXIT cleanup, so remove its non-authoritative files
    # after transaction recovery has preserved the published candidate.
    rm -f \
        "$ROOT_DIR/scripts"/.regen-legacy-hashes.lock.owner-token-claim.* \
        "$ROOT_DIR/scripts"/.regen-legacy-hashes.lock.pid-claim.* \
        "$ROOT_DIR/scripts"/.legacy-skill-hashes.primary.* \
        "$ROOT_DIR/scripts"/.legacy-skill-hashes.recovery.* \
        "$ROOT_DIR/scripts"/.legacy-skill-hashes.transaction.* \
        "$(dirname "$HOOK_MANIFEST")"/.legacy-skill-hashes.mirror.* \
        "$(dirname "$HOOK_MANIFEST")"/.legacy-skill-hashes.recovery.*
}

inject_failure() {
    local point="$1"
    if [[ "${GOPHER_AI_REGEN_FAILPOINT:-}" == "$point" ]]; then
        echo "error: injected legacy hash regeneration failure at $point" >&2
        return 97
    fi
}

if [[ "$CHECK_ONLY" == "true" ]]; then
    if [[ -f "$TRANSACTION_FILE" ]]; then
        echo "error: interrupted legacy hash publication requires a normal regeneration run" >&2
        exit 1
    fi
else
    acquire_lock
    remove_legacy_lock_dir
    recover_interrupted_publication
    remove_abandoned_staging_files
fi

# Collect every blob OID that has ever existed in this branch history at a path
# matching plugins/<plugin>/skills/<skill>/SKILL.md, then emit
# <sha256> <skill_name> pairs. The skill name is necessary to preserve
# per-skill ownership during manifest-based cleanup — a hash that originated
# from skill A must not be accepted as proof of ownership for a candidate in
# directory B.
TMP=$(/usr/bin/mktemp "$TEMP_BASE/gopher-ai-legacy-hashes.body.XXXXXX")

collect_hashes() {
    {
    if [[ -n "${GOPHER_AI_REGEN_TEST_COLLECTION_CHILD:-}" ]]; then
        sleep "${GOPHER_AI_REGEN_TEST_COLLECTION_CHILD_SECONDS:-3}" &
        test_child_pid=$!
        printf '%s\n' "$test_child_pid" > "${GOPHER_AI_REGEN_TEST_COLLECTION_CHILD}.pid"
        touch "${GOPHER_AI_REGEN_TEST_COLLECTION_CHILD}.ready"
        wait "$test_child_pid"
    fi
    git rev-list --objects "$BASE_REF" 2>/dev/null \
        | awk '$2 ~ "^plugins/[^/]+/skills/[^/]+/SKILL[.]md$" {print $1, $2}' \
        | while read -r blob path; do
            skill_name="$(basename "$(dirname "$path")")"
            hash="$(git cat-file blob "$blob" 2>/dev/null | sha256sum | awk '{print $1}')"
            [[ -n "$hash" ]] && echo "$hash $skill_name"
        done

    inject_failure collection

    for skill_file in "$ROOT_DIR"/plugins/*/skills/*/SKILL.md; do
        [[ -f "$skill_file" ]] || continue
        skill_name="$(basename "$(dirname "$skill_file")")"
        hash="$(sha256sum "$skill_file" | awk '{print $1}')"
        [[ -n "$hash" ]] && echo "$hash $skill_name"
    done
    } | sort -u >"$TMP"
}

# Monitor mode gives the background worker and all of its pipeline descendants
# a dedicated process group. Waiting explicitly lets Bash run signal traps
# immediately; cleanup terminates that group and releases the guardian lock.
set -m
collect_hashes &
COLLECTION_PID=$!
set +m
wait "$COLLECTION_PID"
COLLECTION_PID=""

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

mkdir -p "$(dirname "$HOOK_MANIFEST")"
CANDIDATE=$(/usr/bin/mktemp "$TEMP_BASE/gopher-ai-legacy-hashes.manifest.XXXXXX")
{
    printf '%s\n' \
        '# legacy-skill-hashes.txt — manifest of every gopher-ai SKILL.md blob version' \
        '# this repo has ever shipped. Each non-comment line is "<sha256> <skill_name>".' \
        '# Regenerated by scripts/regen-legacy-hashes.sh.' \
        '# Used by scripts/install-codex.sh --cleanup to safely identify legacy gopher-ai' \
        '# installs in ~/.codex/skills/ when running without git history (curl one-liner).' \
        '# Both fields must match for cleanup to consider a candidate gopher-ai-owned —' \
        '# this prevents accepting a hash from skill A as proof of ownership for skill B.' \
        '# DO NOT EDIT BY HAND — re-run the regen script after finalizing SKILL.md changes.' \
        '#'
    printf '# Total entries: %s\n' "$count"
    cat "$TMP"
} > "$CANDIDATE"

# Validate the entire candidate before staging anything beside a destination.
if ! awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    NF != 2 || $1 !~ /^[0-9a-f]+$/ || length($1) != 64 || $2 ~ /[[:space:]]/ { exit 1 }
' "$CANDIDATE"; then
    echo "error: generated legacy hash manifest has an invalid entry" >&2
    exit 1
fi
candidate_count="$(awk '!/^[[:space:]]*#/ && !/^[[:space:]]*$/ { count++ } END { print count + 0 }' "$CANDIDATE")"
if [[ "$candidate_count" != "$count" ]]; then
    echo "error: generated legacy hash manifest count mismatch ($candidate_count != $count)" >&2
    exit 1
fi

STAGED_MANIFEST=$(/usr/bin/mktemp "$ROOT_DIR/scripts/.legacy-skill-hashes.primary.XXXXXX")
STAGED_HOOK_MANIFEST=$(/usr/bin/mktemp "$(dirname "$HOOK_MANIFEST")/.legacy-skill-hashes.mirror.XXXXXX")
cp "$CANDIDATE" "$STAGED_MANIFEST"
cp "$CANDIDATE" "$STAGED_HOOK_MANIFEST"
chmod 0644 "$STAGED_MANIFEST" "$STAGED_HOOK_MANIFEST"
if ! cmp -s "$CANDIDATE" "$STAGED_MANIFEST" ||
   ! cmp -s "$CANDIDATE" "$STAGED_HOOK_MANIFEST"; then
    echo "error: staged legacy hash manifests differ from the validated candidate" >&2
    exit 1
fi

candidate_hash="$(hash_file "$CANDIDATE")"
STAGED_TRANSACTION=$(/usr/bin/mktemp "$ROOT_DIR/scripts/.legacy-skill-hashes.transaction.XXXXXX")
printf '%s\n' "$candidate_hash" > "$STAGED_TRANSACTION"
mv "$STAGED_TRANSACTION" "$TRANSACTION_FILE"
STAGED_TRANSACTION=""

mv "$STAGED_MANIFEST" "$MANIFEST"
STAGED_MANIFEST=""
inject_failure after-primary-publish
mv "$STAGED_HOOK_MANIFEST" "$HOOK_MANIFEST"
STAGED_HOOK_MANIFEST=""

if [[ "$(hash_file "$MANIFEST")" != "$candidate_hash" ]] ||
   [[ "$(hash_file "$HOOK_MANIFEST")" != "$candidate_hash" ]] ||
   ! cmp -s "$MANIFEST" "$HOOK_MANIFEST"; then
    echo "error: legacy hash manifest publication did not produce identical mirrors" >&2
    exit 1
fi
rm -f "$TRANSACTION_FILE"

echo "regenerated: $MANIFEST ($count unique <hash skill_name> pairs from $BASE_REF plus current skills)"
echo "mirrored to: $HOOK_MANIFEST"
