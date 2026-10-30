import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('check_github_ci', Path(__file__).parents[1] / 'scripts/check_github_ci.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class GitHubCIGateTests(unittest.TestCase):
    def run_data(self, **changes):
        data = dict(head_sha='a' * 40, head_repository={'full_name': 'owner/repo'}, event='push',
                    head_branch='main', path='.github/workflows/terraform-ci.yml', run_number=1,
                    run_attempt=1, status='completed', conclusion='success', id=1)
        data.update(changes)
        return data

    def check(self, runs):
        return ci.require_success(runs, 'a' * 40, 'owner/repo')

    def test_matching_commit_succeeds(self):
        self.assertEqual(self.check([self.run_data()])['id'], 1)

    def test_wrong_commit_repo_workflow_branch_or_event_cannot_authorize(self):
        for changes in [dict(head_sha='b' * 40), dict(head_repository={'full_name': 'fork/repo'}),
                        dict(path='.github/workflows/other.yml'), dict(head_branch='feature'), dict(event='pull_request')]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check([self.run_data(**changes)])

    def test_failed_or_running_latest_attempt_blocks_old_success(self):
        for changes in [dict(status='in_progress', conclusion=None), dict(status='completed', conclusion='failure')]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check([self.run_data(), self.run_data(run_attempt=2, **changes)])

    def test_latest_run_blocks_an_older_success(self):
        with self.assertRaises(ValueError):
            self.check([self.run_data(), self.run_data(run_number=2, conclusion='cancelled')])

    def test_missing_run_blocks(self):
        with self.assertRaises(ValueError):
            self.check([])


if __name__ == '__main__':
    unittest.main()
