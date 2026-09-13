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
STAGED_RECOVERY=""
TRANSACTION_IDENTITY=""
LOCK_GUARD_PID=""
LOCK_STATE_DIR=""
LOCK_TRANSACTION_REQUEST=""
LOCK_TRANSACTION_DONE=""
COLLECTION_PID=""

lock_guard_is_running() {
    local job_pid

    while IFS= read -r job_pid; do
        [[ "$job_pid" != "$LOCK_GUARD_PID" ]] || return 0
    done < <(jobs -pr)
    return 1
}

ensure_lock_held() {
    if [[ -z "$LOCK_GUARD_PID" ]] || ! lock_guard_is_running; then
        echo "error: lost legacy hash publication lock" >&2
        return 1
    fi
}

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
    [[ -z "$STAGED_RECOVERY" ]] || rm -f "$STAGED_RECOVERY"
    [[ -z "$TRANSACTION_IDENTITY" ]] || rm -f "$TRANSACTION_IDENTITY"
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
    local writer_pid="$$"

    LOCK_STATE_DIR=$(/usr/bin/mktemp -d "$TEMP_BASE/gopher-ai-legacy-lock.XXXXXX")
    lock_ready="$LOCK_STATE_DIR/ready"
    lock_error="$LOCK_STATE_DIR/error"
    LOCK_TRANSACTION_REQUEST="$LOCK_STATE_DIR/remove-transaction"
    LOCK_TRANSACTION_DONE="$LOCK_STATE_DIR/transaction-removed"

    case "${GOPHER_AI_REGEN_TEST_LOCK_BACKEND:-}" in
        perl|python3)
            backend="$GOPHER_AI_REGEN_TEST_LOCK_BACKEND"
            if ! command -v "$backend" >/dev/null 2>&1; then
                echo "error: requested test lock backend '$backend' is unavailable" >&2
                return 1
            fi
            ;;
        "")
            if command -v perl >/dev/null 2>&1; then
                backend=perl
            elif command -v python3 >/dev/null 2>&1; then
                backend=python3
            else
                echo "error: publication locking requires perl or python3" >&2
                return 1
            fi
            ;;
        *)
            echo "error: unknown test lock backend: $GOPHER_AI_REGEN_TEST_LOCK_BACKEND" >&2
            return 1
            ;;
    esac

    case "$backend" in
        perl)
            perl -MFcntl=:flock -MFile::Glob=:bsd_glob -e '
                my ($path, $ready, $request, $done, $transaction, $hook_manifest, $parent) = @ARGV;
                if (my $delay = $ENV{GOPHER_AI_REGEN_TEST_GUARDIAN_START_DELAY}) {
                    select(undef, undef, undef, $delay);
                }
                exit 2 if getppid() != $parent;
                open(my $lock, ">>", $path) or die "open lock: $!";
                until (flock($lock, LOCK_EX | LOCK_NB)) {
                    exit 2 if getppid() != $parent;
                    select(undef, undef, undef, 0.1);
                }
                exit 2 if getppid() != $parent;
                open(my $signal, ">", $ready) or die "write ready: $!";
                close($signal) or die "close ready: $!";
                while (getppid() == $parent) {
                    if (-e $request && !-e $done) {
                        open(my $command, "<", $request) or die "read transaction cleanup request: $!";
                        my @command = <$command>;
                        close($command) or die "close transaction cleanup request: $!";
                        chomp(@command);
                        my $operation = shift(@command) // "";
                        if ($operation eq "cleanup" && @command == 0) {
                            (my $scripts_dir = $transaction) =~ s{/[^/]+$}{};
                            (my $hooks_dir = $hook_manifest) =~ s{/[^/]+$}{};
                            for my $pattern (
                                "$scripts_dir/.regen-legacy-hashes.lock.owner-token-claim.*",
                                "$scripts_dir/.regen-legacy-hashes.lock.pid-claim.*",
                                "$scripts_dir/.legacy-skill-hashes.primary.*",
                                "$scripts_dir/.legacy-skill-hashes.recovery.*",
                                "$scripts_dir/.legacy-skill-hashes.transaction.*",
                                "$hooks_dir/.legacy-skill-hashes.mirror.*",
                                "$hooks_dir/.legacy-skill-hashes.recovery.*"
                            ) {
                                for my $staged (bsd_glob($pattern)) {
                                    unlink($staged) or die "remove abandoned staging file: $!";
                                }
                            }
                        } elsif ($operation eq "recover" && @command == 3) {
                            my ($identity, $staged_recovery, $destination) = @command;
                            my @marker_stat = stat($transaction);
                            my @identity_stat = stat($identity);
                            @marker_stat && @identity_stat &&
                                $marker_stat[0] == $identity_stat[0] &&
                                $marker_stat[1] == $identity_stat[1]
                                or die "transaction marker identity changed\n";
                            if (my $hold = $ENV{GOPHER_AI_REGEN_TEST_HOLD_AFTER_RECOVERY}) {
                                open(my $hold_ready, ">", "$hold.ready") or die "write recovery hold ready: $!";
                                close($hold_ready) or die "close recovery hold ready: $!";
                                until (-e $hold) {
                                    exit 2 if getppid() != $parent;
                                    select(undef, undef, undef, 0.05);
                                }
                            }
                            if ($staged_recovery ne "" || $destination ne "") {
                                $staged_recovery ne "" && $destination ne ""
                                    or die "incomplete recovery install request\n";
                                rename($staged_recovery, $destination)
                                    or die "install recovered manifest: $!";
                            }
                            @marker_stat = stat($transaction);
                            @marker_stat &&
                                $marker_stat[0] == $identity_stat[0] &&
                                $marker_stat[1] == $identity_stat[1]
                                or die "transaction marker identity changed\n";
                            unlink($transaction) or die "remove transaction marker: $!";
                        } elsif ($operation eq "publish" && @command == 5) {
                            my ($staged_transaction, $identity, $staged_manifest,
                                $manifest, $staged_hook_manifest) = @command;
                            my @staged_stat = stat($staged_transaction);
                            my @identity_stat = stat($identity);
                            @staged_stat && @identity_stat &&
                                $staged_stat[0] == $identity_stat[0] &&
                                $staged_stat[1] == $identity_stat[1]
                                or die "staged transaction identity changed\n";
                            rename($staged_transaction, $transaction)
                                or die "publish transaction marker: $!";
                            rename($staged_manifest, $manifest)
                                or die "publish primary manifest: $!";
                            if (($ENV{GOPHER_AI_REGEN_FAILPOINT} // "") eq "after-primary-publish") {
                                print STDERR "error: injected legacy hash regeneration failure at after-primary-publish\n";
                                exit 97;
                            }
                            rename($staged_hook_manifest, $hook_manifest)
                                or die "publish hook manifest: $!";
                            if (my $hold = $ENV{GOPHER_AI_REGEN_TEST_HOLD_AFTER_MIRROR_PUBLISH}) {
                                open(my $hold_ready, ">", "$hold.ready") or die "write mirror hold ready: $!";
                                close($hold_ready) or die "close mirror hold ready: $!";
                                until (-e $hold) {
                                    exit 2 if getppid() != $parent;
                                    select(undef, undef, undef, 0.05);
                                }
                            }
                            my @marker_stat = stat($transaction);
                            @marker_stat &&
                                $marker_stat[0] == $identity_stat[0] &&
                                $marker_stat[1] == $identity_stat[1]
                                or die "transaction marker identity changed\n";
                            unlink($transaction) or die "remove transaction marker: $!";
                        } else {
                            die "invalid lock guardian request\n";
                        }
                        open(my $ack, ">", $done) or die "write transaction cleanup acknowledgment: $!";
                        close($ack) or die "close transaction cleanup acknowledgment: $!";
                    }
                    select(undef, undef, undef, 0.1);
                }
            ' "$LOCK_FILE" "$lock_ready" "$LOCK_TRANSACTION_REQUEST" \
                "$LOCK_TRANSACTION_DONE" "$TRANSACTION_FILE" "$HOOK_MANIFEST" \
                "$writer_pid" 2> "$lock_error" &
            ;;
        python3)
            python3 -c '
import fcntl, glob, os, sys, time
path, ready, request, done, transaction, hook_manifest, parent_arg = sys.argv[1:]
parent = int(parent_arg)
delay = os.environ.get("GOPHER_AI_REGEN_TEST_GUARDIAN_START_DELAY")
if delay:
    time.sleep(float(delay))
if os.getppid() != parent:
    raise SystemExit(2)
with open(path, "a") as lock:
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except BlockingIOError:
            if os.getppid() != parent:
                raise SystemExit(2)
            time.sleep(0.1)
    if os.getppid() != parent:
        raise SystemExit(2)
    open(ready, "w").close()
    while os.getppid() == parent:
        if os.path.exists(request) and not os.path.exists(done):
            with open(request) as command:
                command = [line.rstrip("\n") for line in command]
            operation, *args = command
            if operation == "cleanup" and len(args) == 0:
                scripts_dir = os.path.dirname(transaction)
                hooks_dir = os.path.dirname(hook_manifest)
                patterns = (
                    os.path.join(scripts_dir, ".regen-legacy-hashes.lock.owner-token-claim.*"),
                    os.path.join(scripts_dir, ".regen-legacy-hashes.lock.pid-claim.*"),
                    os.path.join(scripts_dir, ".legacy-skill-hashes.primary.*"),
                    os.path.join(scripts_dir, ".legacy-skill-hashes.recovery.*"),
                    os.path.join(scripts_dir, ".legacy-skill-hashes.transaction.*"),
                    os.path.join(hooks_dir, ".legacy-skill-hashes.mirror.*"),
                    os.path.join(hooks_dir, ".legacy-skill-hashes.recovery.*"),
                )
                for pattern in patterns:
                    for staged in glob.glob(pattern):
                        os.unlink(staged)
            elif operation == "recover" and len(args) == 3:
                identity, staged_recovery, destination = args
                marker_stat = os.stat(transaction)
                identity_stat = os.stat(identity)
                if (marker_stat.st_dev, marker_stat.st_ino) != (identity_stat.st_dev, identity_stat.st_ino):
                    raise SystemExit("transaction marker identity changed")
                hold = os.environ.get("GOPHER_AI_REGEN_TEST_HOLD_AFTER_RECOVERY")
                if hold:
                    open(hold + ".ready", "w").close()
                    while not os.path.exists(hold):
                        if os.getppid() != parent:
                            raise SystemExit(2)
                        time.sleep(0.05)
                if staged_recovery or destination:
                    if not staged_recovery or not destination:
                        raise SystemExit("incomplete recovery install request")
                    os.replace(staged_recovery, destination)
                marker_stat = os.stat(transaction)
                if (marker_stat.st_dev, marker_stat.st_ino) != (identity_stat.st_dev, identity_stat.st_ino):
                    raise SystemExit("transaction marker identity changed")
                os.unlink(transaction)
            elif operation == "publish" and len(args) == 5:
                staged_transaction, identity, staged_manifest, manifest, staged_hook_manifest = args
                staged_stat = os.stat(staged_transaction)
                identity_stat = os.stat(identity)
                if (staged_stat.st_dev, staged_stat.st_ino) != (identity_stat.st_dev, identity_stat.st_ino):
                    raise SystemExit("staged transaction identity changed")
                os.replace(staged_transaction, transaction)
                os.replace(staged_manifest, manifest)
                if os.environ.get("GOPHER_AI_REGEN_FAILPOINT") == "after-primary-publish":
                    sys.stderr.write("error: injected legacy hash regeneration failure at after-primary-publish\n")
                    raise SystemExit(97)
                os.replace(staged_hook_manifest, hook_manifest)
                hold = os.environ.get("GOPHER_AI_REGEN_TEST_HOLD_AFTER_MIRROR_PUBLISH")
                if hold:
                    open(hold + ".ready", "w").close()
                    while not os.path.exists(hold):
                        if os.getppid() != parent:
                            raise SystemExit(2)
                        time.sleep(0.05)
                marker_stat = os.stat(transaction)
                if (marker_stat.st_dev, marker_stat.st_ino) != (identity_stat.st_dev, identity_stat.st_ino):
                    raise SystemExit("transaction marker identity changed")
                os.unlink(transaction)
            else:
                raise SystemExit("invalid lock guardian request")
            open(done, "w").close()
        time.sleep(0.1)
            ' "$LOCK_FILE" "$lock_ready" "$LOCK_TRANSACTION_REQUEST" \
                "$LOCK_TRANSACTION_DONE" "$TRANSACTION_FILE" "$HOOK_MANIFEST" \
                "$writer_pid" 2> "$lock_error" &
            ;;
    esac
    LOCK_GUARD_PID=$!
    if [[ -n "${GOPHER_AI_REGEN_TEST_LOCK_GUARD_PID_FILE:-}" ]]; then
        printf '%s\n' "$LOCK_GUARD_PID" > "$GOPHER_AI_REGEN_TEST_LOCK_GUARD_PID_FILE"
    fi

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
    ensure_lock_held
    # Deterministic synchronization point used only by the concurrency test.
    if [[ -n "${GOPHER_AI_REGEN_TEST_HOLD_LOCK:-}" ]]; then
        touch "${GOPHER_AI_REGEN_TEST_HOLD_LOCK}.ready"
        while [[ ! -e "$GOPHER_AI_REGEN_TEST_HOLD_LOCK" ]]; do
            ensure_lock_held
            sleep 0.05
        done
    fi
}

run_guardian_command() {
    local request_tmp="$LOCK_TRANSACTION_REQUEST.tmp"
    local guardian_status=1

    rm -f "$LOCK_TRANSACTION_REQUEST" "$LOCK_TRANSACTION_DONE"
    printf '%s\n' "$@" > "$request_tmp"
    mv "$request_tmp" "$LOCK_TRANSACTION_REQUEST"
    while [[ ! -e "$LOCK_TRANSACTION_DONE" ]]; do
        if ! lock_guard_is_running; then
            wait "$LOCK_GUARD_PID" 2>/dev/null && guardian_status=0 || guardian_status=$?
            echo "error: lock guardian failed during legacy hash publication" >&2
            [[ ! -s "$LOCK_STATE_DIR/error" ]] || sed -n '1,5p' "$LOCK_STATE_DIR/error" >&2
            return "$guardian_status"
        fi
        sleep 0.05
    done
    rm -f "$LOCK_TRANSACTION_REQUEST" "$LOCK_TRANSACTION_DONE"
}

install_recovery() {
    run_guardian_command recover "$1" "$2" "$3"
}

publish_manifests() {
    run_guardian_command publish "$@"
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

    STAGED_RECOVERY=$(/usr/bin/mktemp "$(dirname "$destination")/.legacy-skill-hashes.recovery.XXXXXX")
    cp "$source" "$STAGED_RECOVERY"
    chmod 0644 "$STAGED_RECOVERY"
    if [[ "$(hash_file "$STAGED_RECOVERY")" != "$expected_hash" ]]; then
        rm -f "$STAGED_RECOVERY"
        STAGED_RECOVERY=""
        echo "error: recovered manifest failed transaction hash validation" >&2
        return 1
    fi
}

recover_interrupted_publication() {
    local expected_hash=""
    local extra=""
    local manifest_hash=""
    local hook_hash=""
    local recovery_destination=""

    [[ -f "$TRANSACTION_FILE" ]] || return 0
    if ! read -r expected_hash extra < "$TRANSACTION_FILE" ||
       [[ ! "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || [[ -n "$extra" ]]; then
        echo "error: invalid legacy hash publication transaction marker: $TRANSACTION_FILE" >&2
        return 1
    fi

    TRANSACTION_IDENTITY=$(/usr/bin/mktemp "$ROOT_DIR/scripts/.legacy-skill-hashes.transaction.recovery.XXXXXX")
    rm -f "$TRANSACTION_IDENTITY"
    ln "$TRANSACTION_FILE" "$TRANSACTION_IDENTITY"
    ensure_lock_held

    [[ ! -f "$MANIFEST" ]] || manifest_hash="$(hash_file "$MANIFEST")"
    [[ ! -f "$HOOK_MANIFEST" ]] || hook_hash="$(hash_file "$HOOK_MANIFEST")"

    if [[ "$manifest_hash" == "$expected_hash" && "$hook_hash" == "$expected_hash" ]]; then
        : # Both renames landed; only marker cleanup was interrupted.
    elif [[ "$manifest_hash" == "$expected_hash" ]]; then
        stage_recovery_copy "$MANIFEST" "$HOOK_MANIFEST" "$expected_hash"
        recovery_destination="$HOOK_MANIFEST"
    elif [[ "$hook_hash" == "$expected_hash" ]]; then
        stage_recovery_copy "$HOOK_MANIFEST" "$MANIFEST" "$expected_hash"
        recovery_destination="$MANIFEST"
    elif [[ -f "$MANIFEST" && -f "$HOOK_MANIFEST" ]] && cmp -s "$MANIFEST" "$HOOK_MANIFEST"; then
        : # The marker landed but publication had not started.
    else
        echo "error: interrupted legacy hash publication cannot be recovered automatically" >&2
        echo "error: neither manifest matches transaction digest $expected_hash" >&2
        return 1
    fi

    install_recovery "$TRANSACTION_IDENTITY" "$STAGED_RECOVERY" "$recovery_destination"
    STAGED_RECOVERY=""
    rm -f "$TRANSACTION_IDENTITY"
    TRANSACTION_IDENTITY=""
    echo "recovered interrupted legacy hash manifest publication" >&2
}

remove_abandoned_staging_files() {
    # A SIGKILL can bypass EXIT cleanup. Have the guardian enumerate and
    # remove the abandoned non-authoritative files while it still owns the
    # kernel lock, so a dying guardian cannot race a successor's staging.
    run_guardian_command cleanup
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
    if [[ -n "${GOPHER_AI_REGEN_TEST_HOLD_BEFORE_ABANDONED_CLEANUP:-}" ]]; then
        touch "${GOPHER_AI_REGEN_TEST_HOLD_BEFORE_ABANDONED_CLEANUP}.ready"
        while [[ ! -e "$GOPHER_AI_REGEN_TEST_HOLD_BEFORE_ABANDONED_CLEANUP" ]]; do
            sleep 0.05
        done
    fi
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
TRANSACTION_IDENTITY="${STAGED_TRANSACTION}.identity"
ln "$STAGED_TRANSACTION" "$TRANSACTION_IDENTITY"
if [[ -n "${GOPHER_AI_REGEN_TEST_HOLD_AFTER_STAGING:-}" ]]; then
    touch "${GOPHER_AI_REGEN_TEST_HOLD_AFTER_STAGING}.ready"
    while [[ ! -e "$GOPHER_AI_REGEN_TEST_HOLD_AFTER_STAGING" ]]; do
        ensure_lock_held
        sleep 0.05
    done
fi
publish_manifests \
    "$STAGED_TRANSACTION" \
    "$TRANSACTION_IDENTITY" \
    "$STAGED_MANIFEST" \
    "$MANIFEST" \
    "$STAGED_HOOK_MANIFEST"
STAGED_TRANSACTION=""
STAGED_MANIFEST=""
STAGED_HOOK_MANIFEST=""

if [[ "$(hash_file "$MANIFEST")" != "$candidate_hash" ]] ||
   [[ "$(hash_file "$HOOK_MANIFEST")" != "$candidate_hash" ]] ||
   ! cmp -s "$MANIFEST" "$HOOK_MANIFEST"; then
    echo "error: legacy hash manifest publication did not produce identical mirrors" >&2
    exit 1
fi

rm -f "$TRANSACTION_IDENTITY"
TRANSACTION_IDENTITY=""

echo "regenerated: $MANIFEST ($count unique <hash skill_name> pairs from $BASE_REF plus current skills)"
echo "mirrored to: $HOOK_MANIFEST"
