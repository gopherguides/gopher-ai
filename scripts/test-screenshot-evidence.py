import contextlib
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("evidence", ROOT / "shared/scripts/screenshot-evidence.py")
evidence = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evidence)


class ScreenshotEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.temp.cleanup)
        self.run = Path(self.temp.name)
        (self.run / "images").mkdir()
        self.calls = []
        self.version = "gh version 2.100.0 (2026-09-03)"
        self.push = "true"
        self.upload_fails = False
        self.text_fails = False

    def gh(self, args, cwd=None):
        if args == ["--version"]:
            return subprocess.CompletedProcess(args, 0, self.version, "")
        if args[0] == "api":
            return subprocess.CompletedProcess(args, 0, self.push, "")
        body = (Path(cwd) / args[args.index("--body-file") + 1]).read_text()
        self.calls.append((args, body))
        failed = self.upload_fails if "--attach" in args else self.text_fails
        return subprocess.CompletedProcess(args, int(failed), "comment-url", "")

    def record(self, route, status="pass", capture="desktop", exists=True):
        path = evidence.image_path(route, capture)
        if exists:
            (self.run / path).write_bytes(b"png")
        return {"route": route, "capture": capture, "status": status}

    def post(self, records, kind="pr"):
        with patch.object(evidence, "gh", self.gh):
            return evidence.post(self.run, records, "Verdict: FAIL\n{{SCREENSHOTS}}\nFooter", "o/r", "42", kind)

    def test_table_paths_have_exact_matching_attachments_and_route_alt(self):
        self.post([self.record("/"), self.record("/a?q=[x]|z", "fail")])
        args, body = self.calls[0]
        paths = [args[i + 1].split("#", 1)[0] for i, arg in enumerate(args) if arg == "--attach"]
        self.assertEqual(len(paths), 2)
        for path in paths:
            self.assertIn("](" + path + ")", body)
            self.assertTrue((self.run / path).is_file())
        self.assertIn("Screenshot of /", body)
        self.assertNotIn("saved locally", body)

    def test_cap_preserves_failures_and_reports_omissions(self):
        records = [self.record(f"/pass/{i}") for i in range(51)]
        records += [self.record("/failure", "fail")]
        self.post(records)
        args, body = self.calls[0]
        self.assertEqual(args.count("--attach"), 50)
        self.assertIn("Screenshot of /failure", body)
        self.assertIn("2 screenshots omitted", body)

    def test_more_than_fifty_failures_reports_failed_omissions(self):
        self.post([self.record(f"/{i}", "fail") for i in range(51)])
        self.assertIn("1 non-passing", self.calls[0][1])

    def test_old_cli_and_no_push_are_text_only(self):
        for version, push in [("gh version 2.98.0", "true"), ("gh version 2.100.0", "false"), ("unknown", "true")]:
            with self.subTest(version=version, push=push):
                self.version, self.push = version, push
                self.calls = []
                self.assertEqual(self.post([self.record("/")]), 0)
                args, body = self.calls[0]
                self.assertNotIn("--attach", args)
                self.assertNotIn("![", body)
                self.assertIn("Screenshots unavailable", body)
                self.assertIn("Verdict: FAIL", body)

    def test_upload_failure_retries_without_any_image_links(self):
        self.upload_fails = True
        self.assertEqual(self.post([self.record("/", "fail")]), 0)
        self.assertEqual(len(self.calls), 2)
        args, body = self.calls[1]
        self.assertNotIn("--attach", args)
        self.assertNotIn("![", body)
        self.assertIn("upload failed", body)
        self.assertIn("Verdict: FAIL", body)

    def test_text_post_failure_is_not_reported_as_success(self):
        self.upload_fails = self.text_fails = True
        self.assertNotEqual(self.post([self.record("/")]), 0)

    def test_missing_images_do_not_drop_available_images(self):
        self.post([self.record("/missing", "fail", exists=False), self.record("/present")])
        args, body = self.calls[0]
        self.assertEqual(args.count("--attach"), 1)
        self.assertIn("1 screenshots unavailable on disk", body)
        self.assertNotIn(evidence.image_path("/missing", "desktop"), body)

    def test_empty_run_posts_without_preflight_or_dead_links(self):
        self.post([], "issue")
        self.assertEqual(self.calls[0][0][:3], ["issue", "comment", "42"])
        self.assertIn("No screenshots captured", self.calls[0][1])

    def test_names_are_safe_distinct_and_deterministic(self):
        routes = ["/", "/a/b", "/a-b", "/a?b", "/a#b", "/../../x", "/日本語"]
        paths = [evidence.image_path(route, "desktop") for route in routes]
        self.assertEqual(len(paths), len(set(paths)))
        for route, path in zip(routes, paths):
            self.assertEqual(path, evidence.image_path(route, "desktop"))
            self.assertRegex(path, r"^images/[a-z0-9-]+\.png$")
            self.assertNotEqual(path, evidence.image_path(route, "mobile"))

    def test_cli_records_same_path_used_for_capture_and_updates_verdict(self):
        output = io.StringIO()
        with patch.dict(os.environ, {"TMPDIR": str(self.run)}), patch.object(sys, "argv", ["evidence", "init", "--head", "abcdef012345"]), contextlib.redirect_stdout(output):
            self.assertEqual(evidence.main(), 0)
        run = Path(output.getvalue().strip())
        self.assertEqual(run.parent, self.run)
        for status in ["fail", "pass"]:
            argv = ["evidence", "record", "--run", str(run), "--route", "/", "--capture", "desktop", "--status", status]
            with patch.object(sys, "argv", argv):
                self.assertEqual(evidence.main(), 0)
        records = json.loads((run / "manifest.json").read_text())
        self.assertEqual(records, [{"route": "/", "capture": "desktop", "status": "pass"}])
        output = io.StringIO()
        with patch.object(sys, "argv", ["evidence", "path", "--run", str(run), "--route", "/", "--capture", "desktop"]), contextlib.redirect_stdout(output):
            self.assertEqual(evidence.main(), 0)
        self.assertEqual(Path(output.getvalue().strip()), run / evidence.image_path("/", "desktop"))

    def test_api_failure_is_optional_capability(self):
        with patch.object(evidence, "gh", return_value=subprocess.CompletedProcess([], 1, "", "unavailable")):
            self.assertEqual(evidence.attachment_capability("o/r")[0], False)

    def test_symlinks_are_not_uploaded(self):
        record = self.record("/link", exists=False)
        target = self.run / "private.png"
        target.write_bytes(b"private")
        (self.run / evidence.image_path("/link", "desktop")).symlink_to(target)
        self.post([record])
        self.assertNotIn("--attach", self.calls[0][0])

    def test_templates_use_shared_poster_not_unattached_tables(self):
        for relative in ["skills/e2e-verify/pr-results-comment.md", "skills/review-deep/output-format.md", "lib/ship/local-review.md"]:
            content = (ROOT / "plugins/go-workflow" / relative).read_text()
            self.assertIn("screenshot-evidence", content, relative)
            self.assertNotRegex(content, r"!\[[^\]]*\]\([^)]*\.png\)")


if __name__ == "__main__":
    unittest.main()
