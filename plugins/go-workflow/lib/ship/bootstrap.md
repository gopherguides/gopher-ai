# Ship State Bootstrap

Loaded by `skills/ship/SKILL.md` during state setup. Execute this procedure before argument persistence or context discovery.

## 0. State File Bootstrap

Ship has exactly one state owner. A caller embeds ship by supplying both
`CALLER_LOOP_STATE_FILE` and `CALLER_WORKFLOW_STATE_PATH`; ship creates a child
object in that physical file and never initializes another loop. Without both
values, ship is standalone and always resolves the released canonical state
file under the original repository root. A valid legacy standalone file is
migrated in place by `read_loop_state`, preserving its root field names and
phase routing.

Released ship versions could write that standalone file under a linked
worktree. When the canonical primary-root file is absent, ship enumerates the
linked worktree's loop-state files and relocates the candidate only when exactly
one exists and it is valid ship state. It then migrates the schema and fills
only missing root locator fields from the current registered worktree. Multiple
linked candidates, invalid JSON, or state owned by another loop stop without
mutation and name every ambiguous path. An existing canonical state always
wins; linked-worktree strays are ignored in that case.

```bash
source "<PLUGIN_ROOT>/lib/loop-state.sh"

SHIP_EMBEDDED=false
WORKFLOW_STATE_PATH='[]'

if [ -n "${CALLER_LOOP_STATE_FILE:-}" ] || [ -n "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
  if [ -z "${CALLER_LOOP_STATE_FILE:-}" ] || [ -z "${CALLER_WORKFLOW_STATE_PATH:-}" ]; then
    echo "ERROR: Embedded ship requires both caller state file and workflow path."
    exit 1
  fi
  case "$CALLER_LOOP_STATE_FILE" in
    /*) ;;
    *) echo "ERROR: Embedded ship caller state file must be absolute."; exit 1 ;;
  esac
  if [ ! -f "$CALLER_LOOP_STATE_FILE" ] ||
     ! jq -e '.schema_version == 2' "$CALLER_LOOP_STATE_FILE" >/dev/null 2>&1; then
    echo "ERROR: Embedded ship requires an existing v2 caller state file."
    exit 1
  fi

  STATE_FILE="$CALLER_LOOP_STATE_FILE"
  WORKFLOW_STATE_PATH=$(child_workflow_path "$CALLER_WORKFLOW_STATE_PATH" "ship")
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
  SHIP_EMBEDDED=true
  ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')
  WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" '[]')
  REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" '[]')
else
  CURRENT_CHECKOUT_ROOT=$(git rev-parse --show-toplevel)
  ORIGINAL_REPO_ROOT=$(git -C "$CURRENT_CHECKOUT_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
  WORKTREE_PATH="${WORKTREE_PATH:-$CURRENT_CHECKOUT_ROOT}"
  if [ -z "$ORIGINAL_REPO_ROOT" ] || [ "${ORIGINAL_REPO_ROOT#/}" = "$ORIGINAL_REPO_ROOT" ] ||
     [ -z "$WORKTREE_PATH" ] || [ "${WORKTREE_PATH#/}" = "$WORKTREE_PATH" ] || [ ! -d "$WORKTREE_PATH" ]; then
    echo "ERROR: Could not resolve absolute repository paths."
    exit 1
  fi

  CANONICAL_STATE_FILE="$ORIGINAL_REPO_ROOT/.local/state/ship.loop.local.json"
  STATE_FILE="$CANONICAL_STATE_FILE"
  CURRENT_REPO_SLUG=$(cd "$WORKTREE_PATH" && gh api "repos/{owner}/{repo}" --jq '.full_name')
  MIGRATED_LINKED_STATE=false

  if [ ! -f "$CANONICAL_STATE_FILE" ] &&
     [ "$CURRENT_CHECKOUT_ROOT" != "$ORIGINAL_REPO_ROOT" ]; then
    LINKED_STATE_CANDIDATES=()
    for LINKED_STATE_CANDIDATE in "$CURRENT_CHECKOUT_ROOT/.local/state/"*.loop.local.json; do
      [ -f "$LINKED_STATE_CANDIDATE" ] || continue
      LINKED_STATE_CANDIDATES+=("$LINKED_STATE_CANDIDATE")
    done
    if [ "${#LINKED_STATE_CANDIDATES[@]}" -gt 1 ]; then
      echo "ERROR: Ambiguous linked-worktree loop state candidates while canonical ship state '$CANONICAL_STATE_FILE' is absent; refusing migration:"
      printf ' - %s\n' "${LINKED_STATE_CANDIDATES[@]}"
      exit 1
    elif [ "${#LINKED_STATE_CANDIDATES[@]}" -eq 1 ]; then
      LEGACY_STATE_FILE="${LINKED_STATE_CANDIDATES[0]}"
      if ! jq -e '
        type == "object" and
        (.schema_version == null) and
        .loop_name == "ship" and
        (.completion_promise == "SHIPPED" or .completion_promise == "INCOMPLETE")
      ' "$LEGACY_STATE_FILE" >/dev/null 2>&1; then
        echo "ERROR: Invalid linked-worktree legacy ship state '$LEGACY_STATE_FILE': expected released unversioned ship JSON with a SHIPPED or INCOMPLETE promise; refusing migration to '$CANONICAL_STATE_FILE'."
        exit 1
      fi
      mkdir -p "$(dirname "$CANONICAL_STATE_FILE")"
      mv "$LEGACY_STATE_FILE" "$CANONICAL_STATE_FILE"
      MIGRATED_LINKED_STATE=true
      echo "Migrated linked-worktree ship state from '$LEGACY_STATE_FILE' to '$CANONICAL_STATE_FILE'."
    fi
  fi

  EXISTING_PHASE=""
  if [ -f "$STATE_FILE" ]; then
    read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
    if [ "$MIGRATED_LINKED_STATE" = "true" ]; then
      if [ -z "$(get_loop_field "$STATE_FILE" "original_repo_root" '[]')" ]; then
        set_loop_field "$STATE_FILE" "original_repo_root" "$ORIGINAL_REPO_ROOT" '[]'
      fi
      if [ -z "$(get_loop_field "$STATE_FILE" "worktree_path" '[]')" ]; then
        set_loop_field "$STATE_FILE" "worktree_path" "$CURRENT_CHECKOUT_ROOT" '[]'
      fi
      if [ -z "$(get_loop_field "$STATE_FILE" "repo_slug" '[]')" ]; then
        set_loop_field "$STATE_FILE" "repo_slug" "$CURRENT_REPO_SLUG" '[]'
      fi
      read_loop_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
    fi
    EXISTING_PHASE="$PHASE"
  fi

  if [ -n "$EXISTING_PHASE" ]; then
    PERSISTED_ORIGINAL_REPO_ROOT=$(get_loop_field "$STATE_FILE" "original_repo_root" "$WORKFLOW_STATE_PATH")
    PERSISTED_WORKTREE_PATH=$(get_loop_field "$STATE_FILE" "worktree_path" "$WORKFLOW_STATE_PATH")
    PERSISTED_REPO_SLUG=$(get_loop_field "$STATE_FILE" "repo_slug" "$WORKFLOW_STATE_PATH")
    REGISTERED_WORKTREES=$(git -C "$ORIGINAL_REPO_ROOT" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print}')
    if [ "$PERSISTED_ORIGINAL_REPO_ROOT" != "$ORIGINAL_REPO_ROOT" ] ||
       [ -z "$PERSISTED_WORKTREE_PATH" ] ||
       [ "${PERSISTED_WORKTREE_PATH#/}" = "$PERSISTED_WORKTREE_PATH" ] ||
       [ ! -d "$PERSISTED_WORKTREE_PATH" ] ||
       ! printf '%s\n' "$REGISTERED_WORKTREES" | awk -v path="$PERSISTED_WORKTREE_PATH" '$0 == path { found = 1 } END { exit !found }' ||
       [ "$PERSISTED_REPO_SLUG" != "$CURRENT_REPO_SLUG" ]; then
      set_loop_terminal_result "$STATE_FILE" "incomplete" "ship-worktree-path-invalid" "incomplete" "INCOMPLETE"
      echo "WORKFLOW_RESULT=INCOMPLETE"
      echo "WORKFLOW_REASON=ship-worktree-path-invalid"
      echo "<done>INCOMPLETE</done>"
      exit 1
    fi
    WORKTREE_PATH="$PERSISTED_WORKTREE_PATH"
    REPO_SLUG="$PERSISTED_REPO_SLUG"
    echo "Re-entry detected (phase: $EXISTING_PHASE) — skipping setup-loop to preserve state."
  else
    REPO_SLUG="${REPO_SLUG:-$CURRENT_REPO_SLUG}"
  fi

  if [ -z "$EXISTING_PHASE" ]; then
    if [ ! -x "<PLUGIN_ROOT>/scripts/setup-loop.sh" ]; then
      echo "ERROR: Plugin cache stale. Run /gopher-ai-refresh (or refresh-plugins.sh) and restart Claude Code."
      exit 1
    fi
    /bin/bash "<PLUGIN_ROOT>/scripts/setup-loop.sh" "ship" "SHIPPED" 50 "" \
      "$(jq -c . "<PLUGIN_ROOT>/lib/ship/resume-messages.json")" \
      "$STATE_FILE" "[\"SHIPPED\",\"INCOMPLETE\"]"
  fi
  initialize_workflow_state "$STATE_FILE" "$WORKFLOW_STATE_PATH"
fi
```
