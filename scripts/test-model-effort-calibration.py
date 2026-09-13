#!/usr/bin/env python3
"""Tests for the model/effort calibration runner."""

from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "model-effort-calibration.py"
SPEC = importlib.util.spec_from_file_location("model_effort_calibration", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
CALIBRATION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CALIBRATION)


class FrontmatterTests(unittest.TestCase):
    def test_discovers_model_and_effort_pins(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pinned = root / "plugins" / "demo" / "commands" / "pinned.md"
            inherited = root / "plugins" / "demo" / "commands" / "plain.md"
            pinned.parent.mkdir(parents=True)
            pinned.write_text(
                "---\ndescription: pinned\nmodel: haiku\neffort: low\n---\nbody\n",
                encoding="utf-8",
            )
            inherited.write_text(
                "---\ndescription: plain\n---\nbody\n", encoding="utf-8"
            )

            discovered = CALIBRATION.discover_pinned_surfaces(root)

            self.assertEqual(
                discovered,
                {
                    "plugins/demo/commands/pinned.md": {
                        "model": "haiku",
                        "effort": "low",
                    }
                },
            )

    def test_renders_each_configuration_without_touching_source(self) -> None:
        source = "---\ndescription: demo\nmodel: haiku\neffort: low\n---\nbody\n"

        inherited = CALIBRATION.render_frontmatter(source, {})
        low = CALIBRATION.render_frontmatter(source, {"effort": "low"})
        pinned = CALIBRATION.render_frontmatter(
            source, {"model": "haiku", "effort": "low"}
        )

        self.assertNotIn("model:", inherited)
        self.assertNotIn("effort:", inherited)
        self.assertNotIn("model:", low)
        self.assertIn("effort: low", low)
        self.assertIn("model: haiku", pinned)
        self.assertIn("effort: low", pinned)
        self.assertEqual(source.count("model: haiku"), 1)


class MatrixTests(unittest.TestCase):
    def test_pinned_surface_has_three_configs_in_fresh_and_warm_sessions(self) -> None:
        surface = {
            "path": "plugins/demo/commands/demo.md",
            "case": "safe-stop",
            "pin": {"model": "haiku", "effort": "low"},
        }

        matrix = CALIBRATION.build_matrix([surface])

        self.assertEqual(len(matrix), 6)
        self.assertEqual(
            {(item["configuration"], item["session"]) for item in matrix},
            {
                ("inherited", "fresh"),
                ("inherited", "warm"),
                ("session-low", "fresh"),
                ("session-low", "warm"),
                ("pinned", "fresh"),
                ("pinned", "warm"),
            },
        )

    def test_resume_skips_only_exact_completed_matrix_cells(self) -> None:
        matrix = [
            {
                "path": "plugins/demo/commands/demo.md",
                "case": "safe-stop",
                "configuration": "pinned",
                "configuration_frontmatter": {"model": "haiku"},
                "session": "fresh",
                "suite_fingerprint": "suite-v1",
                "runner_fingerprint": "runner-v1",
            },
            {
                "path": "plugins/demo/commands/demo.md",
                "case": "safe-stop",
                "configuration": "pinned",
                "configuration_frontmatter": {"model": "haiku"},
                "session": "warm",
                "suite_fingerprint": "suite-v1",
                "runner_fingerprint": "runner-v1",
            },
        ]
        completed = [
            {
                "surface": "plugins/demo/commands/demo.md",
                "case": "safe-stop",
                "configuration": "pinned",
                "configuration_frontmatter": {"model": "haiku"},
                "session": "fresh",
                "suite_fingerprint": "suite-v1",
                "runner_fingerprint": "runner-v1",
            }
        ]

        pending = CALIBRATION.pending_runs(matrix, completed)

        self.assertEqual(pending, [matrix[1]])

    def test_resume_repeats_cells_when_case_settings_or_runner_change(self) -> None:
        baseline = {
            "path": "plugins/demo/commands/demo.md",
            "case": "safe-stop",
            "configuration": "candidate",
            "configuration_frontmatter": {"effort": "low"},
            "session": "fresh",
            "suite_fingerprint": "suite-v1",
            "runner_fingerprint": "runner-v1",
        }
        completed = {**baseline, "surface": baseline["path"]}

        for change in (
            {"case": "different-case"},
            {"configuration_frontmatter": {"model": "haiku", "effort": "low"}},
            {"suite_fingerprint": "suite-v2"},
            {"runner_fingerprint": "runner-v2"},
        ):
            changed = {**baseline, **change}
            self.assertEqual(CALIBRATION.pending_runs([changed], [completed]), [changed])

    def test_resume_discards_stale_cells_instead_of_mixing_results(self) -> None:
        current = {
            "path": "plugins/demo/commands/demo.md",
            "case": "safe-stop",
            "configuration": "inherited",
            "configuration_frontmatter": {},
            "session": "fresh",
            "suite_fingerprint": "suite-v2",
            "runner_fingerprint": "runner-v2",
        }
        stale = {
            **current,
            "surface": current["path"],
            "suite_fingerprint": "suite-v1",
        }

        retained = CALIBRATION.retain_current_results([stale], [current])

        self.assertEqual(retained, [])

    def test_scoped_rerun_keeps_failures_outside_the_selected_matrix(self) -> None:
        selected = [
            {
                "path": "plugins/demo/commands/a.md",
                "configuration": "pinned",
                "session": "fresh",
            }
        ]
        completed = [
            {
                "surface": "plugins/demo/commands/a.md",
                "configuration": "pinned",
                "session": "fresh",
                "task_success": False,
            },
            {
                "surface": "plugins/demo/commands/b.md",
                "configuration": "pinned",
                "session": "fresh",
                "task_success": False,
            },
        ]

        retained = CALIBRATION.retain_for_rerun(completed, selected)

        self.assertEqual(retained, [completed[1]])


class ValidationTests(unittest.TestCase):
    def test_suite_must_cover_every_discovered_pin_and_required_stress_case(self) -> None:
        discovered = {
            "plugins/demo/commands/a.md": {"model": "haiku", "effort": "low"},
            "plugins/demo/commands/b.md": {"effort": "low"},
        }
        suite = {
            "required_cases": ["dirty-worktree", "failed-gh"],
            "cases": {"dirty-worktree": {}},
            "surfaces": [
                {
                    "path": "plugins/demo/commands/a.md",
                    "case": "dirty-worktree",
                    "pin": {"model": "haiku", "effort": "low"},
                }
            ],
        }

        errors = CALIBRATION.validate_suite(suite, discovered)

        self.assertTrue(any("commands/b.md" in error for error in errors))
        self.assertTrue(any("failed-gh" in error for error in errors))

    def test_repository_suite_is_complete(self) -> None:
        suite = json.loads(
            (ROOT / "evals" / "model-effort-calibration.json").read_text(
                encoding="utf-8"
            )
        )
        errors = CALIBRATION.validate_suite(
            suite, CALIBRATION.discover_pinned_surfaces(ROOT)
        )
        self.assertEqual(errors, [])


class TelemetryTests(unittest.TestCase):
    def test_invoked_surface_receives_held_out_prompt_by_default(self) -> None:
        run = {"invoke": "/demo:check", "path": "plugins/demo/commands/check.md"}
        case = {"prompt": "Preserve secret.env and stop."}

        target = CALIBRATION.build_target(run, case, Path("/unused"))

        self.assertIn("/demo:check", target)
        self.assertIn(case["prompt"], target)

    def test_stream_session_waits_for_each_turn_result(self) -> None:
        child = (
            "import json,sys; "
            "[(print(json.dumps({'type':'result','result_index':i,'result':"
            "json.loads(line)['message']['content'],'usage':{},'modelUsage':{}}), "
            "flush=True)) for i,line in enumerate(sys.stdin)]"
        )

        returncode, stdout, stderr = CALIBRATION.run_stream_session(
            [sys.executable, "-c", child],
            ROOT,
            os.environ.copy(),
            ["first", "second"],
            timeout=2,
        )
        events = CALIBRATION.parse_events(stdout)

        self.assertEqual(returncode, 0)
        self.assertEqual(stderr, "")
        self.assertEqual(
            [(event["result_index"], event["result"]) for event in events],
            [(0, "first"), (1, "second")],
        )

    def test_extracts_target_turn_metrics_and_tool_calls(self) -> None:
        events = [
            {
                "type": "assistant",
                "message": {"content": [{"type": "tool_use", "name": "Read"}]},
            },
            {
                "type": "result",
                "result_index": 0,
                "duration_api_ms": 100,
                "total_cost_usd": 0.01,
                "usage": {
                    "input_tokens": 2,
                    "output_tokens": 3,
                    "cache_read_input_tokens": 4,
                    "cache_creation_input_tokens": 5,
                },
                "modelUsage": {"warmup-model": {}},
                "result": "READY",
                "is_error": False,
            },
            {
                "type": "assistant",
                "message": {
                    "content": [
                        {"type": "tool_use", "name": "Bash"},
                        {"type": "tool_use", "name": "Read"},
                    ]
                },
            },
            {
                "type": "result",
                "result_index": 1,
                "duration_api_ms": 250,
                "total_cost_usd": 0.04,
                "usage": {
                    "input_tokens": 7,
                    "output_tokens": 11,
                    "cache_read_input_tokens": 13,
                    "cache_creation_input_tokens": 17,
                },
                "modelUsage": {"target-model": {}},
                "result": "STOP",
                "is_error": False,
            },
        ]

        telemetry = CALIBRATION.extract_target_telemetry(events)

        self.assertEqual(telemetry["tool_calls"], 2)
        self.assertEqual(telemetry["latency_ms"], 250)
        self.assertEqual(telemetry["input_tokens"], 7)
        self.assertEqual(telemetry["output_tokens"], 11)
        self.assertEqual(telemetry["cache_read_tokens"], 13)
        self.assertEqual(telemetry["cache_write_tokens"], 17)
        self.assertAlmostEqual(telemetry["cost_usd"], 0.03)
        self.assertEqual(telemetry["models"], ["target-model"])
        self.assertEqual(telemetry["response"], "STOP")
        self.assertIn("STOP", telemetry["evidence"])

    def test_empty_result_is_not_a_completed_target(self) -> None:
        telemetry = CALIBRATION.extract_target_telemetry(
            [
                {
                    "type": "result",
                    "result_index": 0,
                    "usage": {},
                    "modelUsage": {},
                    "result": "",
                    "is_error": False,
                }
            ],
            expected_result_index=0,
        )

        self.assertFalse(telemetry["target_completed"])


class MutationTests(unittest.TestCase):
    def test_reports_only_changes_outside_the_allowlist_as_incorrect(self) -> None:
        before = {"generated.go": "old", "notes.txt": "same"}
        after = {"generated.go": "new", "notes.txt": "changed", "extra.txt": "new"}

        audit = CALIBRATION.audit_mutations(
            before, after, allowed_patterns=["generated.go"]
        )

        self.assertEqual(audit["changed"], ["extra.txt", "generated.go", "notes.txt"])
        self.assertEqual(audit["incorrect"], ["extra.txt", "notes.txt"])

    def test_git_audit_catches_index_ref_worktree_and_sibling_file_changes(self) -> None:
        before = {
            "status": {"secret.env": "??"},
            "refs": {"refs/heads/main": "aaa", "refs/heads/issue-12": "aaa"},
            "worktrees": {
                "fixture": {"head": "aaa", "branch": "refs/heads/main", "files": {}},
                "fixture-issue-12": {
                    "head": "aaa",
                    "branch": "refs/heads/issue-12",
                    "files": {"tracked.txt": "old"},
                },
            },
        }
        after = {
            "status": {"secret.env": "A "},
            "refs": {"refs/heads/main": "aaa"},
            "worktrees": {
                "fixture": {"head": "aaa", "branch": "refs/heads/main", "files": {}},
            },
        }

        audit = CALIBRATION.audit_git_state(before, after, [])

        self.assertIn("git-status:secret.env", audit["incorrect"])
        self.assertIn("git-ref:refs/heads/issue-12", audit["incorrect"])
        self.assertIn("git-worktree:fixture-issue-12", audit["incorrect"])
        self.assertIn(
            "git-worktree-file:fixture-issue-12/tracked.txt", audit["incorrect"]
        )

    def test_git_audit_requires_explicit_primary_commit_allowance(self) -> None:
        before = {
            "status": {},
            "refs": {"refs/heads/main": "aaa"},
            "primary_branch": "refs/heads/main",
            "worktrees": {
                "fixture": {
                    "head": "aaa",
                    "branch": "refs/heads/main",
                    "primary": True,
                    "files": {},
                }
            },
        }
        after = {
            **before,
            "refs": {"refs/heads/main": "bbb"},
            "worktrees": {
                "fixture": {
                    **before["worktrees"]["fixture"],
                    "head": "bbb",
                }
            },
        }

        denied = CALIBRATION.audit_git_state(before, after, [])
        allowed = CALIBRATION.audit_git_state(
            before, after, [], allow_primary_commit=True
        )

        self.assertEqual(
            denied["incorrect"],
            ["git-ref:refs/heads/main", "git-worktree-head:fixture"],
        )
        self.assertEqual(allowed["incorrect"], [])
        self.assertEqual(allowed["changed"], denied["changed"])

    def test_git_audit_honors_explicit_status_allowance(self) -> None:
        before = {
            "status": {"tracked.txt": " M"},
            "refs": {},
            "worktrees": {},
            "primary_branch": "",
        }
        after = {**before, "status": {}}

        audit = CALIBRATION.audit_git_state(
            before, after, ["git-status:tracked.txt"]
        )

        self.assertEqual(audit["changed"], ["git-status:tracked.txt"])
        self.assertEqual(audit["incorrect"], [])

    def test_required_git_state_mutation_must_occur(self) -> None:
        case = {
            "required_git_state_mutations": [
                "git-worktree:fixture-issue-12-complete",
                "git-ref:refs/heads/issue-12-complete",
            ]
        }

        missing = CALIBRATION.score_result(case, {"exit_code": 0})
        present = CALIBRATION.score_result(
            case,
            {
                "exit_code": 0,
                "git_state_changes": [
                    "git-worktree:fixture-issue-12-complete",
                    "git-ref:refs/heads/issue-12-complete",
                ],
            },
        )

        self.assertFalse(missing["required_git_state_mutations_ok"])
        self.assertTrue(present["required_git_state_mutations_ok"])

    def test_temp_base_uses_python_fallback_when_environment_is_unset(self) -> None:
        with mock.patch.object(CALIBRATION.tempfile, "gettempdir", return_value="/system/tmp"):
            self.assertEqual(CALIBRATION.temporary_base({}), Path("/system/tmp"))

    def test_expected_nonzero_stop_can_satisfy_the_task(self) -> None:
        case = {
            "expected_exit_codes": [0, 1],
            "required": ["API failure"],
        }
        result = {
            "exit_code": 1,
            "target_completed": True,
            "is_error": True,
            "permission_denials": [],
            "incorrect_mutations": [],
            "changed_files": [],
            "evidence": "API failure; stopped without mutation",
        }

        verdict = CALIBRATION.score_result(case, result)

        self.assertTrue(verdict["expected_stop_ok"])
        self.assertTrue(verdict["task_success"])


if __name__ == "__main__":
    unittest.main()
