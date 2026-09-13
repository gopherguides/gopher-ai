# Model and Effort Calibration Results for Issue 427

Issue #427 replaces judgment-based Claude model and effort overrides with a
repeatable held-out evaluation. The suite, runner, and machine-readable results
are checked in at:

- `evals/model-effort-calibration.json`
- `scripts/model-effort-calibration.py`
- `evals/model-effort-calibration-results-427.json`

## Method

The runner discovered every `model:` or `effort:` frontmatter override and
evaluated each surface under three configurations:

1. inherited session settings;
2. the session model at `effort: low`;
3. the surface's pinned configuration, or a proposed configuration for an
   unpinned control.

Each configuration ran once in a fresh session and once after three warm-up
turns containing 24,000 characters of stable context. The 27 surfaces and 15
held-out cases produced 162 runs. Fixtures exercised dirty and unmerged work,
failed `gh` calls, similar branch names, generated-code failures,
cancellation-sensitive state, and Tailwind workspace/CSS preservation.

A run passed only when the target turn completed, its exit behavior was
expected, required rubric evidence appeared, tool permissions held, required
mutations occurred, and the filesystem/Git audit found no mutation outside the
case allowlist. The Git audit covers status/index state, refs, registered
worktrees, and files in linked sibling worktrees in addition to the primary
fixture snapshot. Every run records task success, incorrect mutations, tool
calls, latency, input/output tokens, cache reads/writes, and estimated cost.
Raw transcripts are omitted from the committed artifact; hashes and byte counts
remain for provenance.

## Outcome

- 132 of 162 runs passed.
- No run made an incorrect filesystem, index, ref, branch, or worktree
  mutation.
- The 30 task failures were safe stops or incomplete rubric outcomes. Their
  configuration clusters drove demotions: Haiku cancellation passed 8/12
  candidate cells, Haiku exploration passed 0/2, Haiku worktree removal passed
  1/2, the effective Haiku Tailwind audit surfaces passed 2/4, and Haiku
  initialization passed 0/2.
- The runner recorded no transport/setup error and every target turn completed.

Configuration labels in the results reflect the final policy: `pinned` is a
retained or promoted override and `candidate` is an evaluated override left
unset. Each run also preserves its exact `configuration_frontmatter`.

## Decisions

| Decision | Surfaces | Evidence |
|---|---|---|
| Retain Haiku + low | Both `clear-cache` surfaces, `create-worktree`, and `gopher-ai-refresh` | 8/8 pinned fresh/warm runs passed with zero incorrect mutations. Model-level savings outweighed cache recreation. |
| Retain Sonnet | `quality-review-prompt`, `spec-review-prompt` | 4/4 pinned runs passed. Combined pinned latency and cost were materially below inherited execution. |
| Promote Haiku + low | `prune-worktree` | 2/2 pinned runs rejected similar issue branch names without changing refs, registered worktrees, or sibling files. Cost fell from $0.168 inherited to $0.044 pinned. |
| Remove effort-only overrides | Both `lint-fix` surfaces, both `validate-skills` surfaces, `commit`, `changelog`, `standup`, `weekly-summary` | Low effort passed 32/32 repeated runs with no incorrect mutation, but warm runs averaged $0.175 versus $0.128 inherited, a 36% cache-recreation increase. |
| Remove Haiku + low | Six `cancel-loop` command/skill surfaces | Only 8/12 candidate fresh/warm runs completed the cancellation rubric. No incorrect mutation occurred, but the quality gate is all-or-nothing. |
| Remove Haiku | `explore-prompt` | Haiku failed 0/2 fresh/warm rubric checks; inherited passed 2/2 while session-low also failed 0/2. |
| Remove redundant inherit | `implementer-prompt` | Explicit `model: inherit` did not select a distinct execution tier, so retaining the override had no measurable purpose. |
| Keep inherited | `remove-worktree` | Inherited passed 2/2 against an actual matching dirty/unmerged linked worktree; Haiku passed 1/2. No removal, ref change, index change, or sibling-file change escaped the audit. |
| Keep inherited | Tailwind `audit` command/skill and `init` command | The effective audit command/skill candidates passed 2/4, and initialization passed 0/2. No Tailwind override was promoted. |

The prune promotion is narrow: it is justified by the exact
branch-disambiguation fixture in this sweep. Other destructive workflows
continue to inherit, and the pin should be rechecked when a rolling model alias
changes behavior.

## Reproduction

Validate suite coverage without calling a model:

```bash
python3 scripts/model-effort-calibration.py --validate
python3 scripts/test-model-effort-calibration.py
```

Run or resume a sweep with bounded parallelism:

```bash
python3 scripts/model-effort-calibration.py \
  --run --resume --jobs 3 \
  --output model-effort-calibration-results.json
```

The runner checkpoints each completed cell atomically, supports scoped surface,
configuration, and session filters, and treats a failed cell as evidence rather
than aborting the remaining matrix. Resume identities include the suite and
runner fingerprints, case, exact settings, surface, and session, so changed
calibration inputs replace stale cells instead of mixing results.
