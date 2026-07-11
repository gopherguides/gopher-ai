# Adaptive Review Planning

All review entry points use `scripts/review-plan.sh`; do not recreate size guards in callers.

Run the planner before invoking a reviewer:

```bash
REVIEW_PLAN_ARGS=(
  --base "$REVIEW_BASE"
  --backend "$REVIEW_BACKEND"
  --concurrency "$REVIEW_CONCURRENCY"
)
if [ -n "${SCOPE_HINT:-}" ]; then
  REVIEW_PLAN_ARGS+=(--scope "$SCOPE_HINT")
fi
REVIEW_PLAN=$("${CLAUDE_PLUGIN_ROOT}/scripts/review-plan.sh" "${REVIEW_PLAN_ARGS[@]}")
printf '%s\n' "$REVIEW_PLAN"
REVIEW_PLAN_MODE=$(printf '%s\n' "$REVIEW_PLAN" | sed -n 's/^REVIEW_PLAN_MODE=//p')
REVIEW_PLAN_REQUIRES_INPUT=$(printf '%s\n' "$REVIEW_PLAN" | sed -n 's/^REVIEW_PLAN_REQUIRES_INPUT=//p')
REVIEW_PLAN_CONCURRENT=$(printf '%s\n' "$REVIEW_PLAN" | sed -n 's/^REVIEW_PLAN_CONCURRENT=//p')
```

The plan measures unified-diff lines separately from Git additions, deletions,
files, and bytes. It classifies generated, vendored, lockfile, binary,
deletion-only, and whitespace-only mechanical changes. Its effective scope
combines semantic volume, relevant file count, topology, and backend capacity.

Follow the displayed plan:

1. For `full-context`, review the complete diff in one pass.
2. For `partitioned`, give each review unit its listed files plus the full
   issue/PR context and construct that unit's diff from those paths. Run units concurrently only when
   `REVIEW_PLAN_CONCURRENT=yes`; otherwise process every unit sequentially.
3. Treat low-information units intentionally: verify generated artifacts
   against their source or generator, vendored and lockfile integrity against
   the dependency change, binary provenance, deletion reachability, and
   mechanical behavior preservation.
4. Run the final coordinator pass over the full checkout. Check interfaces,
   callers, shared state, dependency boundaries, and every changed source file
   against the plan so no relevant file is omitted.
5. Verify every candidate finding against the current checkout and requirements.
   Discard stale or speculative findings, deduplicate by root cause and code
   location, then rank the remaining findings by priority and confidence.

An unusually large plan is review-risk information, not an interruption. Ask
the user only when `REVIEW_PLAN_REQUIRES_INPUT=yes` or partitioning exposes a
material product decision. An explicit `--scope` changes emphasis, not baseline
coverage.
