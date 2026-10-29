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

    def test_manual_review_targets_the_selected_pull_request(self):
        workflow = yaml.safe_load((ROOT / '.github/workflows/gopher-ai-review.yml').read_text())
        events = workflow.get('on', workflow.get(True))
        self.assertTrue(events['workflow_dispatch']['inputs']['pr_number']['required'])
        steps = workflow['jobs']['review']['steps']
        review = next(step for step in steps if step.get('id') == 'review')
        self.assertNotIn('if', review)
        self.assertEqual(review['with']['pr-number'], '${{ inputs.pr_number || github.event.pull_request.number }}')
        self.assertEqual(review['with']['head-sha'], '${{ steps.pr.outputs.head_sha }}')


if __name__ == '__main__':
    unittest.main()
