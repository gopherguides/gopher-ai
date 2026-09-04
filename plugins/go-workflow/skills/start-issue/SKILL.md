---
name: start-issue
description: "Start implementation of a GitHub issue: fetch context, prepare worktree flow, implement with TDD, verify, and submit PR. Use for 'start issue #N', issue URLs, or requests to begin issue work. SKIP fully autonomous issue-to-merge requests; use complete-issue."
argument-hint: "<issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
disable-model-invocation: true
---

# Start Issue

## Plugin Resource Resolution

`<PLUGIN_ROOT>` is notation. Replace it with a concrete absolute plugin root before every resource read or command:

- **Codex:** Start from the directory containing the absolute selected `SKILL.md` path, then ascend two directories (`skills/<name>` -> plugin root).
- **Claude Code:** Bind it to the injected `${CLAUDE_PLUGIN_ROOT}` value.

Before requesting decisions, entering a planning workflow, or delegating work,
read `<PLUGIN_ROOT>/lib/driver-interaction.md` and follow its
cross-platform capability-binding rules.

Read `<PLUGIN_ROOT>/lib/decision-gates.md` before resolving any workflow
choice.

Bind the invocation arguments as `SKILL_ARGS` for `$go-workflow:start-issue` by reading `<PLUGIN_ROOT>/lib/skill-arguments.md` with this Claude Code compatibility payload:
<claude-skill-arguments>
$ARGUMENTS
</claude-skill-arguments>

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

## Embedded Workflow Contract

Start-issue is embedded only when both caller variables are explicitly set.
Never infer composition from a generic inherited `STATE_FILE`:

```bash
EMBEDDED_WORKFLOW=false
source "<PLUGIN_ROOT>/lib/loop-state.sh"
CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
RESOLVED_ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')
if [ -z "$RESOLVED_ORIGINAL_REPO_ROOT" ] || [ "${RESOLVED_ORIGINAL_REPO_ROOT#/}" = "$RESOLVED_ORIGINAL_REPO_ROOT" ] || [ ! -d "$RESOLVED_ORIGINAL_REPO_ROOT" ]; then
  echo "Error: Could not resolve the absolute primary worktree root."
  exit 1
fi
if [ -n "${CALLER_LOOP_STATE_FILE:-}" ] && [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  EMBEDDED_WORKFLOW=true
  STATE_FILE="$CALLER_LOOP_STATE_FILE"
  WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "start_issue")
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
elif [ -n "${CALLER_LOOP_STATE_FILE:-}" ] || [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  echo "Error: Embedded start-issue requires both caller state variables."
  exit 1
else
  ORIGINAL_REPO_ROOT="$RESOLVED_ORIGINAL_REPO_ROOT"
  STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/start-issue-$ISSUE_NUM.loop.local.json"
  mkdir -p "$(dirname "$STATE_FILE")"
  STATE_FILE=$(cd "$(dirname "$STATE_FILE")" && pwd)/$(basename "$STATE_FILE")
  WORKFLOW_STATE_PATH='[]'
  WORKTREE_PATH="$CURRENT_CHECKOUT_ROOT"
  REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
fi
```

When embedded, every phase and field operation uses `STATE_FILE` plus
`WORKFLOW_STATE_PATH`. Start-issue never changes the root completion promise or
terminal allowlist, never initializes another loop, and returns only through
`set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" RESULT REASON PHASE`.

## Loop Initialization

```bash
EXISTING_PHASE=""
if [ -f "$STATE_FILE" ]; then
  read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  EXISTING_PHASE="$PHASE"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ] || [ -n "$EXISTING_PHASE" ]; then
  PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  PERSISTED_WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
  CURRENT_REPO_SLUG=$(cd "$CURRENT_CHECKOUT_ROOT" && gh api "repos/{owner}/{repo}" --jq '.full_name')
  REGISTERED_WORKTREES=$(git -C "$RESOLVED_ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / { sub(/^worktree /, ""); print }')
  if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$RESOLVED_ORIGINAL_REPO_ROOT" ] ||
     [ -z "$PERSISTED_WORKTREE_PATH" ] ||
     [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
     [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
     ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit found ? 0 : 1 }' ||
     [ -z "$PERSISTED_REPO_SLUG" ] ||
     [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
    WORKFLOW_REASON=start-issue-worktree-path-invalid
    if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
      set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$WORKFLOW_REASON" "incomplete"
      echo "START_ISSUE_RESULT=incomplete"
      echo "START_ISSUE_REASON=$WORKFLOW_REASON"
    else
      set_loop_terminal_result "$STATE_FILE" "incomplete" "$WORKFLOW_REASON" "incomplete" "INCOMPLETE"
      echo "<done>INCOMPLETE</done>"
    fi
    exit 1
  fi
  ORIGINAL_REPO_ROOT="$PERSISTED_ORIGINAL_REPO_ROOT"
  WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
  REPO_SLUG="$PERSISTED_REPO_SLUG"
fi

if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  echo "Embedded start-issue is using the caller-owned loop state."
elif [ -n "$EXISTING_PHASE" ]; then
  echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop."
elif [ ! -x "<PLUGIN_ROOT>/scripts/setup-loop.sh" ]; then
  echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."
  exit 1
else
  /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "start-issue-$ISSUE_NUM" "COMPLETE" "" "" '{}' \
    "$STATE_FILE" '["COMPLETE","INCOMPLETE"]'
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
  set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_PATH" '[]'
  set_loop_field "$STATE_FILE" "repo_slug" "$REPO_SLUG" '[]'
fi
```

`ORIGINAL_REPO_ROOT`, `WORKTREE_PATH`, `STATE_FILE`, and `REPO_SLUG` are
resolved once before any worktree transition. Do not derive them again from
the ambient shell directory.

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

## Worktree Detection & Decision (BEFORE Plan Mode)

First, check if already running inside a git worktree:

```bash
IN_WORKTREE=false
GIT_DIR_ABS=$(git -C "$WORKTREE_PATH" rev-parse --absolute-git-dir 2>/dev/null)
GIT_COMMON_REL=$(git -C "$WORKTREE_PATH" rev-parse --git-common-dir 2>/dev/null)
GIT_COMMON_ABS=$(cd "$WORKTREE_PATH" && cd "$GIT_COMMON_REL" && pwd)
if [ -n "$GIT_DIR_ABS" ] && [ -n "$GIT_COMMON_ABS" ] && [ "$GIT_DIR_ABS" != "$GIT_COMMON_ABS" ]; then
  IN_WORKTREE=true
fi
```

This resolves both `--git-dir` and `--git-common-dir` to absolute paths via
`cd ... && pwd`, then compares them. In the main repo (even from a subdirectory)
both resolve to the same absolute `.git` path. In a linked worktree, `--git-dir`
resolves to `.git/worktrees/<name>` while `--git-common-dir` resolves to `.git`.

**If `IN_WORKTREE=true`:** Skip the worktree question entirely. Proceed directly
to "Plan Mode Check" (the "No, work in current directory" path). Display:

```text
Already running in a worktree — skipping worktree creation.
```

**If `IN_WORKTREE=false`:** resolve this as a **driver-resolvable gate** before
planning:

1. Use the current checkout when the request or execution environment already
   provides isolation, or when the checkout is a clean non-default feature
   branch dedicated to this issue.
2. Create a worktree when the user explicitly requested one or when the current
   checkout is the shared default checkout and isolation is available.
3. Otherwise use the current checkout and create the required feature branch.

State `Decision`, `Evidence`, and `Rationale` as defined by
`decision-gates.md`, then continue. Do not request input for this technical
choice.

---

## If the driver selected "create worktree"

→ Read `<PLUGIN_ROOT>/lib/start-issue/worktree-create.md` and follow the
full procedure: capture `SOURCE_DIR`, derive `WORKTREE_NAME`/`BRANCH_NAME` from
issue title, fetch and create the worktree, search for env files
(`.env`/`.env.local`/`.envrc`) and offer to copy with directory structure
preserved, capture `WORKTREE_ABS_PATH`, register the compatibility worktree
state file, and confirm to the user.

After the worktree is established, continue to **Plan Mode Check** below.

Persist the selected worktree in the root physical-context fields of the same
caller-owned file:

```bash
set_loop_field "$STATE_FILE" "worktree_path" "$WORKTREE_ABS_PATH" '[]'
```

## If the driver selected "work in current directory"

Continue to **Step 1: Detect Issue Type** below. You will create a branch in the
appropriate workflow step.

**Now** use the active surface's planning capability to create a plan for the
implementation. If no native planning capability is available, write and
maintain an explicit plan as required by the cross-platform binding rules.

---

## Plan Mode Check (AFTER worktree is established)

**Now** enter the active surface's planning workflow to create a plan for the
implementation. If no native planning workflow is available, write and
maintain an explicit plan.

**CRITICAL: When writing your plan, include these facts at the top of the plan
file:**

If a worktree was created:

```markdown
## Working Directory
All work MUST happen in: <the concrete WORKTREE_PATH value>
Original repo (state only): <the ORIGINAL_REPO_ROOT value>
Every repository command and file path must explicitly target the worktree.
Do not rely on a pre-tool-use hook to reject an ambient-directory operation.
```

If no worktree:

```markdown
## Working Directory
Working in current directory. A feature branch will be created.
```

If you ARE already in plan mode, continue with the workflow below.

---

## MANDATORY: All Work Happens in the Worktree

**Your shell CWD does NOT persist between Bash calls.** Every repository command
must explicitly target `WORKTREE_PATH`; a prior `cd` is never evidence of scope.

| Tool | How to use the worktree path |
|------|------------------------------|
| **Bash** | Prefer `git -C "$WORKTREE_PATH"`, `go -C "$WORKTREE_PATH"`, and `gh ... --repo "$REPO_SLUG"`; use `(cd "$WORKTREE_PATH" && ...)` only when a command has no directory option |
| **Read** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Edit** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Write** | Use `$WORKTREE_PATH/path/to/file` as the `file_path` |
| **Glob** | Set `path` parameter to `$WORKTREE_PATH` |
| **Grep** | Set `path` parameter to `$WORKTREE_PATH` |

No hook is assumed to enforce this invariant. Each command and file operation
must be correct on its own.

**Self-check before EVERY file operation:** "Does this path start with
`$WORKTREE_PATH`?" If not, STOP and fix it.

**Note:** When using a worktree, the branch is already
`issue-<num>-<title>`. Skip the "Create Branch" step in the workflows below.

Continue to **Step 1: Detect Issue Type** below.

---

## Branch Protection Check

**CRITICAL:** Before starting any work, verify you will NOT commit to
main/master.

This workflow creates feature branches (`fix/` or `feat/`). If you are
currently on `main`, `master`, or the default branch:

- **If worktree was created**: You should already be on the `issue-<num>-<title>` branch
- **If working in current directory**: A branch will be created in Step 3 (Bug) or Step 4 (Feature)

**NEVER commit directly to main/master.** Always ensure a feature branch exists
before making any code changes.

---

## Step 1: Detect Issue Type

Analyze the issue to determine if it's a **bug fix** or **new feature**.

**Check labels first** (most reliable):

- Bug indicators: `bug`, `fix`, `defect`, `error`, `regression`, `crash`
- Feature indicators: `enhancement`, `feature`, `feat`, `new`, `improvement`, `request`

**If no clear labels, analyze title and body:**

- Bug patterns: "fix", "broken", "error", "fail", "crash", "doesn't work", "issue with", "problem", "bug", "regression", "incorrect"
- Feature patterns: "add", "implement", "create", "new", "support", "enable", "allow", "introduce", "enhance"

**If still uncertain after labels, title, body, comments, and acceptance
criteria**, this is a **missing-intent gate**. Request: "The issue semantics
remain ambiguous. Should this follow the bug-fix or feature workflow?" If
structured input is unavailable, ask in the final response and stop before
branch creation, implementation, or a completion claim.

---

## Implementation Workflow

### Orchestrated selection

When the Surface Dispatch Decision selected `<PLUGIN_ROOT>/lib/start-issue/orchestrated-workflow.md`, follow its
full 12-step procedure: duplicate check (bugs only), branch creation, Explore
delegation, design approach (features only), task decomposition and
parallel-dispatch decision, Implementer delegation (parallel or sequential),
spec-compliance review, quality review, verify
(build/test/lint), Step 9.5 coverage gate, security review, submit (PR template
detection + creation), watch CI.

### Manual selection

When the Surface Dispatch Decision selected
`<PLUGIN_ROOT>/lib/start-issue/manual-workflow.md`, follow its
single-session bug and feature flows. Both follow the same shape: explore/design
→ TDD red (IRON LAW: no implementation code before failing tests) → green →
verify → coverage → security → submit → watch CI.

---

## Verification Gate (HARD — applies before ANY completion signal)

Before outputting `<done>COMPLETE</done>`, every claim MUST have FRESH evidence
from THIS session — actual command output, not narrative:

- **"Tests pass"** → `go -C "$WORKTREE_PATH" test ./...` output with "ok" lines, zero failures
- **"Build succeeds"** → `go -C "$WORKTREE_PATH" build ./...` exit 0
- **"Lint clean"** → `(cd "$WORKTREE_PATH" && golangci-lint run)` output (skip if not installed)
- **"CI passes"** → `gh pr checks "$PR_NUM" --repo "$REPO_SLUG"` with all checks green

**Red-flag language check** — if you are about to write "should work" / "should
be fine" / "probably" / "likely" / "I believe this fixes…" / "I think this
resolves…" / "Done!" / "Complete!" without preceding command output proving it,
STOP and run verification instead.

**Do NOT commit, push, or create a PR without fresh verification evidence.**

## Workflow Result Contract

Every terminal path persists a result before it returns. For an incomplete
outcome, use the supplied machine-readable reason:

```bash
START_ISSUE_REASON="${WORKFLOW_REASON:?workflow reason is required}"
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "incomplete" "$START_ISSUE_REASON" "incomplete"
  echo "START_ISSUE_RESULT=incomplete"
  echo "START_ISSUE_REASON=$START_ISSUE_REASON"
else
  set_loop_terminal_result "$STATE_FILE" "incomplete" "$START_ISSUE_REASON" "incomplete" "INCOMPLETE"
  echo "<done>INCOMPLETE</done>"
fi
```

Stop after this block. The embedded branch returns control to its caller and
does not emit a terminal marker.

## Completion Criteria

**DO NOT output `<done>COMPLETE</done>` until ALL of these are TRUE:**

1. Code changes implemented and address the issue
2. Tests written and ALL PASS (`go -C "$WORKTREE_PATH" test ./...` or equivalent) — with output shown above
3. Coverage verified for changed source files, or not applicable because the
   diff is source-free / all changed Go files are `package main`
4. Linting passes (`(cd "$WORKTREE_PATH" && golangci-lint run)` or equivalent, if installed) — with output shown above
5. Changes committed with a proper commit message
6. Changes pushed to the remote branch
7. PR created and the PR URL displayed
8. CI checks pass (`gh pr checks "$PR_NUM" --repo "$REPO_SLUG"` shows all green) — with output shown above

When all criteria are met, persist the successful structured result. Embedded
start-issue then returns control to its caller; standalone start-issue emits its
own completion marker:

```bash
if [ "$EMBEDDED_WORKFLOW" = "true" ]; then
  set_workflow_result "$STATE_FILE" "$WORKFLOW_STATE_PATH" "complete" "" "completed"
  echo "START_ISSUE_RESULT=complete"
else
  set_loop_terminal_result "$STATE_FILE" "complete" "" "completed" "COMPLETE"
  echo "<done>COMPLETE</done>"
fi
```

This signals the loop to exit. If you output this prematurely, the issue will
not be properly resolved.

**Safety note:** If you've iterated 15+ times without success, document the
blocking evidence and stop incomplete. Do not treat the iteration limit as
permission to bypass completion criteria.

Use extended thinking for complex analysis.

## Further Reading

- `<PLUGIN_ROOT>/lib/start-issue/worktree-create.md` — full worktree creation procedure (env-file copy, state-file registration)
- `<PLUGIN_ROOT>/lib/start-issue/orchestrated-workflow.md` — 12-step subagent-orchestrated flow (Explore → Implementer → spec/quality review → verify → coverage → security → submit → CI)
- `<PLUGIN_ROOT>/lib/start-issue/manual-workflow.md` — single-session bug + feature flows for `--no-agents`
