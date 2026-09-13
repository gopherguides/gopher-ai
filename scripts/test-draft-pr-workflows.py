#!/usr/bin/env python3
"""Check PR admission and merge-queue coverage without running CI payloads."""
from pathlib import Path
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
GUARD = "github.event_name != 'pull_request' || github.event.pull_request.draft == false"


class WorkflowAdmissionTests(unittest.TestCase):
    def test_pr_workflows(self):
        workflows = list((ROOT / '.github/workflows').glob('*.yml'))
        self.assertTrue(workflows)
        for path in workflows:
            with self.subTest(workflow=path.name):
                workflow = yaml.safe_load(path.read_text())
                events = workflow.get('on', workflow.get(True))
                if 'pull_request' not in events:
                    continue
                self.assertEqual(set(events['pull_request']['types']),
                                 {'opened', 'synchronize', 'reopened', 'ready_for_review'})
                self.assertIn('merge_group', events)
                for name, job in workflow['jobs'].items():
                    with self.subTest(job=name):
                        self.assertIn(GUARD, job.get('if', ''))

    def test_review_only_calls_pr_api_for_pr_events(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/gopher-ai-review.yml').read_text())
        steps = workflow['jobs']['review']['steps']
        review = next(step for step in steps if step.get('id') == 'review')
        self.assertEqual(review.get('if'), "github.event_name == 'pull_request'")


if __name__ == '__main__':
    unittest.main()
