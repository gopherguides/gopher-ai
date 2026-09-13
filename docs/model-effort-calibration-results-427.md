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
turns containing 24,000 characters of stable context. The 27 surfaces and 14
held-out cases produced 162 runs. Fixtures exercised dirty and unmerged work,
failed `gh` calls, similar branch names, generated-code failures,
cancellation-sensitive state, and Tailwind workspace/CSS preservation.

A run passed only when the target turn completed, its exit behavior was
expected, required rubric evidence appeared, tool permissions held, required
mutations occurred, and the filesystem/Git audit found no mutation outside the
case allowlist. Every run records task success, incorrect mutations, tool
calls, latency, input/output tokens, cache reads/writes, and estimated cost.
Raw transcripts are omitted from the committed artifact; hashes and byte counts
remain for provenance.

## Outcome

- 155 of 162 runs passed.
- One run incorrectly edited `zz_generated.go`; it used the session model at
  low effort for the lint-fix command.
- The other six failures made no incorrect mutation: Haiku exploration failed
  both sessions, Haiku Tailwind initialization failed both sessions, and the
  effective Tailwind audit skill failed both Haiku sessions.
- All inherited configurations passed.

Configuration labels in the results reflect the final policy: `pinned` is a
retained or promoted override and `candidate` is an evaluated override left
unset. Each run also preserves its exact `configuration_frontmatter`.

## Decisions

| Decision | Surfaces | Evidence |
|---|---|---|
| Retain Haiku + low | Six `cancel-loop` command/skill surfaces, both `clear-cache` surfaces, `create-worktree`, and `gopher-ai-refresh` | 20/20 pinned fresh/warm runs passed with zero incorrect mutations. Model-level savings outweighed cache recreation. |
| Retain Sonnet | `quality-review-prompt`, `spec-review-prompt` | 4/4 pinned runs passed. Combined pinned latency and cost were materially below inherited execution. |
| Promote Haiku + low | `prune-worktree`, `remove-worktree` | 4/4 candidate runs preserved dirty/unmerged work and rejected similar branch names. Combined cost fell from $0.437 inherited to $0.112 pinned; latency fell from 82.0s to 48.7s. |
| Remove effort-only overrides | Both `lint-fix` surfaces, both `validate-skills` surfaces, `commit`, `changelog`, `standup`, `weekly-summary` | Low effort passed 31/32 repeated runs but caused the only incorrect mutation. Across these surfaces, warm low-effort runs averaged $0.179 versus $0.116 inherited, a 55% increase from cache recreation. |
| Remove Haiku | `explore-prompt` | Haiku failed 0/2 fresh/warm rubric checks; inherited and session-low each passed 2/2. |
| Remove redundant inherit | `implementer-prompt` | Explicit `model: inherit` did not select a distinct execution tier, so retaining the override had no measurable purpose. |
| Keep inherited | Tailwind `audit` command/skill and `init` command | The standalone audit command candidate passed 2/2, but the same-named skill that supplies real invocation metadata failed 0/2. Initialization also failed 0/2. No Tailwind override was promoted. |

The worktree cleanup promotion is narrow: it is justified by the exact
dirty-worktree and branch-disambiguation fixtures in this sweep. Other
destructive workflows continue to inherit, and these pins should be rechecked
when a rolling model alias changes behavior.

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
  --output "${TMPDIR}/model-effort-calibration-results.json"
```

The runner checkpoints each completed cell atomically, supports scoped surface,
configuration, and session filters, and treats a failed cell as evidence rather
than aborting the remaining matrix.
