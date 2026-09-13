#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for router_name in ship start-issue address-review complete-issue review-deep; do
  router_file="$ROOT_DIR/plugins/go-workflow/skills/$router_name/SKILL.md"
  router_bytes=$(wc -c < "$router_file")
  injected_prefix=$(head -c 8000 "$router_file")

  case "$router_name" in
    ship)
      required_routes='lib/ship/bootstrap.md lib/ship/reentry.md lib/ship/context.md lib/ship/local-review.md lib/ship/push-and-pr.md lib/ship/ci-watch.md lib/ship/bot-watch.md lib/ship/address-bots.md lib/ship/merge.md'
      required_contracts='one canonical state file|exact-head CI|UI-visible changes require passing E2E|Never use admin override|Standalone success|Embedded success'
      ;;
    start-issue)
      required_routes='lib/start-issue/setup.md lib/start-issue/loop-state.md lib/start-issue/workspace.md lib/start-issue/manual-workflow.md lib/start-issue/orchestrated-workflow.md lib/start-issue/ci-monitoring.md'
      required_contracts='missing issue number|Workspace Before Planning|manual-workflow.md|orchestrated-workflow.md|exact pushed head|Embedded success'
      ;;
    address-review)
      required_routes='skills/address-review/entry.md skills/address-review/loop-management.md skills/address-review/setup-and-discovery.md skills/address-review/checkout-rebase.md skills/address-review/fetch-feedback.md skills/address-review/fix-cycle.md skills/address-review/completion-check.md skills/address-review/watch-loop.md'
      required_contracts='--no-watch|REVIEW_CLEAN=true|Steps 2-11 only|exact-head CI|Standalone|Embedded'
      ;;
    complete-issue)
      required_routes='skills/complete-issue/arguments.md skills/complete-issue/loop-state.md skills/complete-issue/implementation-handoff.md skills/complete-issue/self-review.md skills/complete-issue/verification-handoff.md skills/complete-issue/codex-fallback.md'
      required_contracts='Owner phase routing|must stay in trunk|child path in|start-issue/SKILL.md|e2e-verify/SKILL.md|INCOMPLETE'
      ;;
    review-deep)
      required_routes='skills/review-deep/arguments.md skills/review-deep/scope-discovery.md skills/review-deep/context-gathering.md skills/review-deep/static-analysis.md skills/review-deep/review-criteria.md skills/review-deep/fix-and-verify.md skills/review-deep/output-format.md'
      required_contracts='Action matrix|Ordered Review Pipeline|PR-backed default|Branch-only default|review-owned|incomplete'
      ;;
  esac

  if [ "$router_bytes" -ge 6000 ]; then
    echo "FAIL: $router_name router is ${router_bytes} bytes; expected less than 6000"
    exit 1
  fi

  for required_route in $required_routes; do
    if [[ "$injected_prefix" != *"<PLUGIN_ROOT>/$required_route"* ]]; then
      echo "FAIL: $router_name Codex injection cannot reach $required_route"
      exit 1
    fi
    if [ ! -f "$ROOT_DIR/plugins/go-workflow/$required_route" ]; then
      echo "FAIL: $router_name route $required_route does not resolve"
      exit 1
    fi
  done

  old_ifs=$IFS
  IFS='|'
  for required_contract in $required_contracts; do
    if [[ "$injected_prefix" != *"$required_contract"* ]]; then
      echo "FAIL: $router_name Codex injection omits $required_contract"
      exit 1
    fi
  done
  IFS=$old_ifs

  echo "OK: $router_name router is ${router_bytes} bytes with mandatory routes in the injected prefix"
done

echo "All go-workflow router budget tests passed."
