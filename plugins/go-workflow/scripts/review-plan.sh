#!/bin/bash
set -euo pipefail

BASE=""
BACKEND="codex"
CONCURRENCY="auto"
SCOPE=""

usage() {
  echo "usage: review-plan.sh --base <revision> [--backend <name>] [--concurrency auto|yes|no] [--scope <hint>]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base) [ "$#" -ge 2 ] || usage; BASE="$2"; shift 2 ;;
    --backend) [ "$#" -ge 2 ] || usage; BACKEND="$2"; shift 2 ;;
    --concurrency) [ "$#" -ge 2 ] || usage; CONCURRENCY="$2"; shift 2 ;;
    --scope) [ "$#" -ge 2 ] || usage; SCOPE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$BASE" ] || usage
git rev-parse --verify "$BASE^{commit}" >/dev/null 2>&1 || {
  echo "review-plan: base revision not found: $BASE" >&2
  exit 1
}

case "$CONCURRENCY" in auto|yes|no) ;; *) usage ;; esac
case "$BACKEND" in
  codex) CAPACITY=16000; MAX_UNITS=8; BACKEND_CONCURRENT=yes ;;
  gemini) CAPACITY=14000; MAX_UNITS=8; BACKEND_CONCURRENT=yes ;;
  fable) CAPACITY=12000; MAX_UNITS=6; BACKEND_CONCURRENT=yes ;;
  agent) CAPACITY=10000; MAX_UNITS=6; BACKEND_CONCURRENT=yes ;;
  ollama) CAPACITY=6000; MAX_UNITS=4; BACKEND_CONCURRENT=no ;;
  *) CAPACITY=8000; MAX_UNITS=4; BACKEND_CONCURRENT=no ;;
esac

if [ "$CONCURRENCY" = auto ]; then
  CONCURRENT="$BACKEND_CONCURRENT"
elif [ "$CONCURRENCY" = yes ]; then
  CONCURRENT=yes
else
  CONCURRENT=no
fi

RANGE="$BASE...HEAD"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gopher-ai-review-plan.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
RECORDS="$TMP_DIR/records.tsv"
CONCERNS="$TMP_DIR/concerns.txt"
: > "$RECORDS"
: > "$CONCERNS"

UNIFIED_LINES=$(git diff --no-ext-diff "$RANGE" | wc -l | tr -d ' ')
DIFF_BYTES=$(git diff --no-ext-diff --binary "$RANGE" | wc -c | tr -d ' ')
FILES=0 ADDITIONS=0 DELETIONS=0 SEMANTIC=0 GENERATED=0 VENDORED=0
LOCKFILES=0 BINARY=0 DELETION_ONLY=0 MECHANICAL=0 RELEVANT=0 EFFECTIVE_CHANGES=0

while IFS= read -r -d '' record; do
  IFS="$(printf '\t')" read -r added deleted path <<< "$record"
  old_path=""
  status=""
  if [ -z "${path:-}" ]; then
    IFS= read -r -d '' old_path
    IFS= read -r -d '' path
    status=R
  fi
  [ -n "${path:-}" ] || continue
  FILES=$((FILES + 1))
  if [ -z "$status" ]; then
    status=$(git diff --name-status "$RANGE" -- "$path" | awk 'NR == 1 { print $1 }')
  fi
  category=semantic
  relevant=yes

  if [ "$added" = - ] || [ "$deleted" = - ]; then
    category=binary; relevant=no; added=0; deleted=0; BINARY=$((BINARY + 1))
  else
    ADDITIONS=$((ADDITIONS + added))
    DELETIONS=$((DELETIONS + deleted))
    case "$path" in
      vendor/*|*/vendor/*|third_party/*|*/third_party/*|node_modules/*|*/node_modules/*)
        category=vendored; relevant=no; VENDORED=$((VENDORED + 1)) ;;
      go.sum|*/go.sum|go.work.sum|*/go.work.sum|package-lock.json|*/package-lock.json|npm-shrinkwrap.json|*/npm-shrinkwrap.json|yarn.lock|*/yarn.lock|pnpm-lock.yaml|*/pnpm-lock.yaml|Cargo.lock|*/Cargo.lock|Gemfile.lock|*/Gemfile.lock|composer.lock|*/composer.lock|poetry.lock|*/poetry.lock|uv.lock|*/uv.lock)
        category=lockfile; relevant=no; LOCKFILES=$((LOCKFILES + 1)) ;;
      generated/*|*/generated/*|gen/*|*/gen/*|*.gen.*|*_generated.go|*zz_generated.*|*.pb.go|*.pb.cc|*.pb.h|*.min.js|*.min.css)
        category=generated; relevant=no; GENERATED=$((GENERATED + 1)) ;;
      *)
        if [ "${status#D}" != "$status" ] || { [ "$added" -eq 0 ] && [ "$deleted" -gt 0 ]; }; then
          category=deletion-only; DELETION_ONLY=$((DELETION_ONLY + 1))
        elif [ -n "$old_path" ] && git diff -w --quiet "$RANGE" -- "$old_path" "$path"; then
          category=mechanical; MECHANICAL=$((MECHANICAL + 1))
        elif [ -z "$old_path" ] && git diff -w --quiet "$RANGE" -- "$path"; then
          category=mechanical; MECHANICAL=$((MECHANICAL + 1))
        else
          SEMANTIC=$((SEMANTIC + 1))
        fi
        ;;
    esac
  fi

  if [ "$relevant" = yes ]; then
    RELEVANT=$((RELEVANT + 1))
    if [ "$category" = deletion-only ]; then
      EFFECTIVE_CHANGES=$((EFFECTIVE_CHANGES + ((added + deleted + 3) / 4)))
    elif [ "$category" = mechanical ]; then
      EFFECTIVE_CHANGES=$((EFFECTIVE_CHANGES + ((added + deleted + 7) / 8)))
    else
      EFFECTIVE_CHANGES=$((EFFECTIVE_CHANGES + added + deleted))
    fi
    case "$path" in
      */*) concern=$(printf '%s' "$path" | awk -F/ '{ print (NF > 2 ? $1 "/" $2 : $1) }') ;;
      *) concern=repository-root ;;
    esac
    printf '%s\n' "$concern" >> "$CONCERNS"
  else
    concern="$category-verification"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$category" "$concern" "$added" "$deleted" "$status" "$path" >> "$RECORDS"
done < <(git diff --numstat -z "$RANGE")

TOPOLOGY=$(sort -u "$CONCERNS" | awk 'NF { count++ } END { print count + 0 }')
EFFECTIVE_SCOPE=$((EFFECTIVE_CHANGES + (RELEVANT * 100) + (TOPOLOGY * 300)))
MODE=full-context
if [ "$EFFECTIVE_SCOPE" -gt "$CAPACITY" ] || [ "$RELEVANT" -gt 30 ] || [ "$TOPOLOGY" -gt 4 ]; then MODE=partitioned; fi
REQUIRES_INPUT=no
if [ "$EFFECTIVE_SCOPE" -gt $((CAPACITY * MAX_UNITS)) ]; then REQUIRES_INPUT=yes; fi

echo "Review statistics"
echo "  unified diff: ${UNIFIED_LINES} lines, ${DIFF_BYTES} bytes"
echo "  actual changes: +${ADDITIONS} -${DELETIONS} across ${FILES} files"
echo "  classifications: semantic=${SEMANTIC}, generated=${GENERATED}, vendored=${VENDORED}, lockfile=${LOCKFILES}, binary=${BINARY}, deletion-only=${DELETION_ONLY}, mechanical=${MECHANICAL}"
echo "Review coverage plan"
echo "  backend: ${BACKEND} (capacity=${CAPACITY}, concurrent=${CONCURRENT})"
echo "  effective scope: ${EFFECTIVE_SCOPE}; mode: ${MODE}; relevant files: ${RELEVANT}; topology groups: ${TOPOLOGY}"
[ -z "$SCOPE" ] || echo "  explicit focus: $SCOPE (coverage remains repository-wide)"

unit=0
if [ "$MODE" = full-context ]; then
  unit=$((unit + 1))
  echo "  unit ${unit}: full relevant diff"
  awk -F '\t' '$1 != "generated" && $1 != "vendored" && $1 != "lockfile" && $1 != "binary" { print "    - " $6 " [" $1 "]" }' "$RECORDS"
else
  while IFS= read -r concern; do
    [ -n "$concern" ] || continue
    unit=$((unit + 1))
    echo "  unit ${unit}: ${concern}"
    awk -F '\t' -v concern="$concern" '$2 == concern { print "    - " $6 " [" $1 "]" }' "$RECORDS"
  done < <(sort -u "$CONCERNS")
fi

for category in generated vendored lockfile binary; do
  count=$(awk -F '\t' -v category="$category" '$1 == category { count++ } END { print count + 0 }' "$RECORDS")
  if [ "$count" -gt 0 ]; then
    unit=$((unit + 1))
    echo "  unit ${unit}: ${category} integrity verification"
    awk -F '\t' -v category="$category" '$1 == category { print "    - " $6 }' "$RECORDS"
  fi
done

echo "  final pass: cross-cutting interfaces, dependencies, and omitted-file audit"
if [ "$REQUIRES_INPUT" = yes ]; then
  echo "Coverage status: requires user input; effective scope exceeds ${MAX_UNITS} reliable ${BACKEND} review units"
else
  execution=sequential
  [ "$CONCURRENT" = yes ] && execution=concurrent
  echo "Coverage status: complete; execute units ${execution}, then verify and coordinate findings"
fi
echo "REVIEW_PLAN_MODE=$MODE"
echo "REVIEW_PLAN_REQUIRES_INPUT=$REQUIRES_INPUT"
echo "REVIEW_PLAN_CONCURRENT=$CONCURRENT"
