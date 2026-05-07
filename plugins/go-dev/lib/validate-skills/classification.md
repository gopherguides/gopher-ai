# Validate-Skills — Command Classification

Loaded by `commands/validate-skills.md` Step 4. Defines the three safety
tiers that determine which blocks are eligible for safe execution
(GREEN only).

A block's tier is the **highest (most restrictive) tier** of ANY command
found anywhere in the block. Parse all commands on each line, including
chained commands separated by `;`, `&&`, `||`, and pipe targets after `|`.
This prevents destructive commands from hiding behind a GREEN prefix
(e.g., `echo ok; rm -rf /` is RED, not GREEN).

## GREEN — Read-Only, Safe to Execute

```
echo, cat, grep, rg, jq, mktemp, ls, pwd, date, command, basename,
dirname, wc, sort, head, tail, tr, cut, sed (without -i), printf, test,
[, true, false, type, which, readlink, realpath, stat, file, diff, comm,
uniq, export
```

## YELLOW — Conditionally Safe, Syntax Check Only

```
awk, env, tee, find (without -exec, -delete, -execdir), git log,
git status, git diff, git branch, git show, git rev-parse, git remote,
curl (without pipe to sh/bash/eval), wget (without pipe to sh/bash/eval),
go build, go vet, go test, go list, go mod, go version, golangci-lint,
npm, npx, node, docker, gh
```

**Why YELLOW (not GREEN):** `awk`, `env`, and `tee` can execute arbitrary
subprocesses (`awk 'BEGIN{system(...)}'`, `env bash -c '...'`) or write
to arbitrary files. `find` with `-exec` / `-delete` / `-execdir` mutates
the filesystem. `curl`/`wget` piped to a shell becomes RED. Plain
`go test` may execute arbitrary code in test files.

## RED — Never Execute, Report as Warning

```
rm, rmdir, dd, sudo, eval, exec, kill, killall, mkfs, mount, umount,
chmod, chown, git push, git reset --hard, git clean, git checkout .,
git restore ., curl | sh, curl | bash, wget | sh, wget | bash,
any pipe to sh/bash/eval/exec
```

For each RED-tier command found, emit a `warning` finding (not an error
— RED commands may be intentional in documentation or guarded contexts).
