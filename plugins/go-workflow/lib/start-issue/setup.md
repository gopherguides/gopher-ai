# Start-Issue Setup and Context

Loaded by `skills/start-issue/SKILL.md` during entry setup and again after durable state bootstrap for repository context. Execute the named sections in router order.

## Empty Arguments

If `SKILL_ARGS` is empty or not provided, explain:

> This skill starts work on a GitHub issue, automatically detecting whether it's
> a bug fix or new feature and following the appropriate workflow.
>
> **Claude Code:** `/go-workflow:start-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>]`
>
> **Codex:** `$go-workflow:start-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>]`
>
> **Example:** `/go-workflow:start-issue 123` or `$go-workflow:start-issue 123 --coverage-threshold 80`
>
> **Options:**
> - `--skip-coverage`: Compatibility hint for source-free changes; changed
>   source files still run coverage verification
> - `--coverage-threshold <n>`: Override default 60% coverage threshold
> - `--no-agents`: Use single-session workflow instead of subagent dispatch (for small/simple issues)
>
> **Workflow:**
> 1. Fetch issue details, labels, and comments
> 2. Optionally create a git worktree for isolated work
> 3. Auto-detect issue type (bug vs feature)
> 4. Create `fix/` or `feat/` branch (or use worktree branch)
> 5. For bugs: Check duplicates → TDD red-green → verify → **coverage check** → security review
> 6. For features: Plan approach → TDD red-green → verify → **coverage check** → security review
> 7. Commit, push, and create PR

This is a **missing-intent gate**. Request the issue number: "What issue number
would you like to work on?" If structured input is unavailable, ask in the final
response and stop without initializing the loop or claiming completion.

## Output Durability

Any artifact this skill produces — commit messages, PR titles and bodies,
GitHub issue comments — describes modules, contracts, and observable behavior,
not file paths, line numbers, or current internal layout. Acceptance criteria
are stated as behaviors a reviewer can verify, not as file diffs. The artifact
must remain interpretable after a future refactor.

## Clear Stale Worktree State

Clear any leftover worktree state from a prior session so it cannot affect a
fresh `$go-workflow:start-issue` invocation:

```bash
/bin/bash "<PLUGIN_ROOT>/scripts/worktree-state.sh" clear 2>/dev/null || true
```

## Security Validation & Flag Parsing

Strip optional flags and extract the issue number:

```bash
ISSUE_NUM=$(echo "$SKILL_ARGS" | sed 's/--skip-coverage//g; s/--coverage-threshold *[0-9]*//g; s/--no-agents//g' | tr -d ' ')
HAS_SKIP=$(echo "$SKILL_ARGS" | grep -q '\-\-skip-coverage' && echo "true" || echo "false")
COV_THRESH=$(echo "$SKILL_ARGS" | grep -oE '\-\-coverage-threshold [0-9]+' | awk '{print $2}' || true)
NO_AGENTS=$(echo "$SKILL_ARGS" | grep -q '\-\-no-agents' && echo "true" || echo "false")
if ! echo "$ISSUE_NUM" | grep -qE '^[0-9]+$'; then
  echo "Error: Issue number must be numeric."
  echo "Claude Code: /go-workflow:start-issue <number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  echo "Codex: \$go-workflow:start-issue <number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  exit 1
fi
echo "Issue: $ISSUE_NUM | skip-coverage: $HAS_SKIP | coverage-threshold: ${COV_THRESH:-60} | no-agents: $NO_AGENTS"
```

The output above shows the parsed issue number and flag values.

**CRITICAL: From this point forward, use `$ISSUE_NUM` (the numeric issue number
shown above) everywhere you would use `SKILL_ARGS`.** The raw `SKILL_ARGS` may
contain flags and MUST NOT be passed to `gh issue view`, branch names, worktree
names, or state file paths.

Store the parsed flags:

- `SKIP_COVERAGE`: compatibility hint from `--skip-coverage`; it never waives
  changed-source coverage
- `COVERAGE_THRESHOLD`: the value after `--coverage-threshold`, or `60` if not specified
- `NO_AGENTS`: `true` if `--no-agents` was passed, `false` otherwise

## Surface Dispatch Decision

Bind the active assistant surface from the current driver, not installed
executables, environment variables, or prompt frontmatter, then select:

- `NO_AGENTS=true`: read `<PLUGIN_ROOT>/lib/start-issue/manual-workflow.md` and use the single-session workflow on every surface.
- `NO_AGENTS=false` on Claude Code: read `<PLUGIN_ROOT>/lib/start-issue/orchestrated-workflow.md` and use its Claude Code binding.
- `NO_AGENTS=false` on Codex: use the orchestrated workflow only when the native delegation capability supports `explorer`, `worker`, and `default`; otherwise explain why native orchestration is unavailable, then read the manual workflow and continue in the current session.

## Context

Gather context before worktree or plan decisions:

```bash
gh issue view "$ISSUE_NUM" --repo "$REPO_SLUG" --json title,state,body,labels,comments --jq '.'
git -C "$WORKTREE_PATH" branch --show-current
git -C "$WORKTREE_PATH" remote show origin 2>/dev/null | grep 'HEAD branch' | sed 's/.*: //' || echo "main"
basename "$WORKTREE_PATH"
git -C "$WORKTREE_PATH" worktree list
```

---
