# Complete-Issue Arguments

Loaded by `SKILL.md` during entry setup. Execute the full parse and missing-target gate before loop initialization.

## Parse Arguments

```bash
ISSUE_NUM=""
FLAGS=""
SKIP_NEXT=false
for arg in $SKILL_ARGS; do
  if [ "$SKIP_NEXT" = "true" ]; then
    FLAGS="$FLAGS $arg"
    SKIP_NEXT=false
  elif [ "$arg" = "--coverage-threshold" ]; then
    FLAGS="$FLAGS $arg"
    SKIP_NEXT=true
  elif echo "$arg" | grep -qE '^--'; then
    FLAGS="$FLAGS $arg"
  elif [ -z "$ISSUE_NUM" ] && echo "$arg" | grep -qE '^[0-9]+$'; then
    ISSUE_NUM="$arg"
  else
    FLAGS="$FLAGS $arg"
  fi
done

if [ -z "$ISSUE_NUM" ]; then
  echo "Claude Code: /go-workflow:complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
  echo "Codex: \$go-workflow:complete-issue <issue-number> [--skip-coverage] [--coverage-threshold <n>] [--no-agents]"
fi

echo "Issue: $ISSUE_NUM | Flags: $FLAGS"
```

If `ISSUE_NUM` is empty, this is a **missing-intent gate**. Request the issue
number through native structured input when available; otherwise ask in the
final response and stop before loop initialization or a completion claim.
