#!/bin/bash

GITHUB_CHECKS_FAILED=1
GITHUB_CHECKS_REGISTRATION_TIMEOUT=2
GITHUB_CHECKS_API_ERROR=3
GITHUB_CHECKS_HEAD_SHIFT=4

github_pr() {
  local pr_number="${1:?PR number is required}"

  gh api "repos/{owner}/{repo}/pulls/$pr_number"
}

github_current_pr() {
  local branch="${1:-}"
  local head_sha="${2:-}"
  local pages

  if [ -z "$branch" ]; then
    branch=$(git branch --show-current)
  fi
  if [ -z "$head_sha" ]; then
    head_sha=$(git rev-parse HEAD)
  fi

  pages=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/$head_sha/pulls?per_page=100") || return
  jq -cer --arg branch "$branch" --arg head_sha "$head_sha" '
    [
      .[][]
      | select(.state == "open")
      | select(.head.ref == $branch)
      | select(.head.sha == $head_sha)
    ]
    | if length == 1 then
        .[0]
      elif length == 0 then
        empty
      else
        error("multiple open pull requests match the current branch and head")
      end
  ' <<< "$pages"
}

github_pr_reviews() {
  local pr_number="${1:?PR number is required}"
  local pages

  pages=$(gh api --paginate --slurp "repos/{owner}/{repo}/pulls/$pr_number/reviews?per_page=100") || return
  jq -c '[.[][]]' <<< "$pages"
}

github_check_snapshot() {
  local head_sha="${1:?Head SHA is required}"
  local check_pages
  local combined_status

  check_pages=$(gh api --paginate --slurp "repos/{owner}/{repo}/commits/$head_sha/check-runs?per_page=100") || return
  combined_status=$(gh api "repos/{owner}/{repo}/commits/$head_sha/status") || return

  jq -cn \
    --arg sha "$head_sha" \
    --argjson check_pages "$check_pages" \
    --argjson combined_status "$combined_status" '
      [
        $check_pages[]?.check_runs[]?
      ]
      | sort_by([(.app.slug // ""), .name, .id])
      | group_by([(.app.slug // ""), .name])
      | map(max_by(.id))
      | map(
          . as $run
          | {
              kind: "check-run",
              id: ("check-run:" + ($run.app.slug // "") + ":" + $run.name),
              source_id: $run.id,
              name: $run.name,
              state: (
                if $run.status == "completed" then
                  ($run.conclusion // "unknown")
                else
                  $run.status
                end
              ),
              terminal: ($run.status == "completed"),
              successful: (
                $run.status == "completed"
                and ($run.conclusion as $conclusion | ["success", "neutral", "skipped"] | index($conclusion) != null)
              )
            }
        ) as $checks
      | [
          $combined_status.statuses[]?
        ]
        | sort_by([.context, .id])
        | group_by(.context)
        | map(max_by(.id))
        | map(
            . as $status
            | {
                kind: "status",
                id: ("status:" + $status.context),
                source_id: $status.id,
                name: $status.context,
                state: $status.state,
                terminal: ($status.state != "pending"),
                successful: ($status.state == "success")
              }
          ) as $statuses
      | {
          sha: $sha,
          items: (($checks + $statuses) | sort_by(.id))
        }
    '
}

github_watch_pr_checks() {
  local pr_number="${1:?PR number is required}"
  local expected_sha="${2:-}"
  local registration_attempts="${GITHUB_CHECK_REGISTRATION_ATTEMPTS:-12}"
  local stability_polls="${GITHUB_CHECK_STABILITY_POLLS:-2}"
  local poll_seconds="${GITHUB_CHECK_POLL_SECONDS:-10}"
  local pr_json
  local current_sha
  local snapshot=""
  local item_count=0
  local attempt=1
  local registered=false
  local pending_count
  local failure_count
  local signature
  local stable_signature=""
  local stable_count=0

  if ! pr_json=$(github_pr "$pr_number"); then
    return "$GITHUB_CHECKS_API_ERROR"
  fi
  current_sha=$(jq -er '.head.sha' <<< "$pr_json") || return "$GITHUB_CHECKS_API_ERROR"

  if [ -n "$expected_sha" ] && [ "$current_sha" != "$expected_sha" ]; then
    return "$GITHUB_CHECKS_HEAD_SHIFT"
  fi
  expected_sha="$current_sha"

  while [ "$attempt" -le "$registration_attempts" ]; do
    if ! snapshot=$(github_check_snapshot "$expected_sha"); then
      return "$GITHUB_CHECKS_API_ERROR"
    fi
    item_count=$(jq '.items | length' <<< "$snapshot") || return "$GITHUB_CHECKS_API_ERROR"
    if [ "$item_count" -gt 0 ]; then
      registered=true
      break
    fi
    if [ "$attempt" -lt "$registration_attempts" ]; then
      sleep "$poll_seconds"
    fi
    attempt=$((attempt + 1))
  done

  if [ "$registered" != "true" ]; then
    return "$GITHUB_CHECKS_REGISTRATION_TIMEOUT"
  fi

  while true; do
    pending_count=$(jq '[.items[] | select(.terminal == false)] | length' <<< "$snapshot") || return "$GITHUB_CHECKS_API_ERROR"
    signature=$(jq -r '[.items[] | "\(.id):\(.source_id)"] | sort | join("|")' <<< "$snapshot") || return "$GITHUB_CHECKS_API_ERROR"

    if [ "$pending_count" -eq 0 ]; then
      if [ "$signature" = "$stable_signature" ]; then
        stable_count=$((stable_count + 1))
      else
        stable_signature="$signature"
        stable_count=1
      fi
      if [ "$stable_count" -ge "$stability_polls" ]; then
        break
      fi
    else
      stable_signature=""
      stable_count=0
    fi

    sleep "$poll_seconds"
    if ! snapshot=$(github_check_snapshot "$expected_sha"); then
      return "$GITHUB_CHECKS_API_ERROR"
    fi
  done

  if ! pr_json=$(github_pr "$pr_number"); then
    return "$GITHUB_CHECKS_API_ERROR"
  fi
  current_sha=$(jq -er '.head.sha' <<< "$pr_json") || return "$GITHUB_CHECKS_API_ERROR"
  if [ "$current_sha" != "$expected_sha" ]; then
    return "$GITHUB_CHECKS_HEAD_SHIFT"
  fi

  printf '%s\n' "$snapshot"
  failure_count=$(jq '[.items[] | select(.terminal and (.successful | not))] | length' <<< "$snapshot") || return "$GITHUB_CHECKS_API_ERROR"
  if [ "$failure_count" -gt 0 ]; then
    return "$GITHUB_CHECKS_FAILED"
  fi
}
