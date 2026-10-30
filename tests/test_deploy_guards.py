"""Prueba bloqueos antes de que Terraform pueda tocar infraestructura."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).parents[1] / 'scripts/jenkins_terraform.sh'


class DeploymentGuardTests(unittest.TestCase):
    def run_guard(self, account='123456789012', state_result='{"Contents": []}', state_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            programs = {
                'git': "#!/bin/bash\nprintf '%s\\n' " + 'a' * 40 + '\n',
                'aws': f'''#!/bin/bash
if [[ "$1" == sts ]]; then printf '%s\\n' '{account}'; else
printf '%s\\n' '{state_result}'
exit {state_exit}
fi
''',
                'terraform': '#!/bin/bash\ntouch terraform-was-called\nexit 99\n',
            }
            for name, content in programs.items():
                path = folder / name
                path.write_text(content)
                path.chmod(0o700)
            env = dict(os.environ, PATH=f'{folder}:' + os.environ['PATH'],
                       AWS_ACCOUNT_ID='123456789012', STATE_BUCKET='example-state-bucket',
                       STATE_KEY='aws-lab/terraform.tfstate', DEPLOY_COMMIT='a' * 40,
                       SSH_ALLOWED_CIDR='192.0.2.10/32', AWS_DEFAULT_REGION='us-east-1',
                       ALLOW_EMPTY_STATE='false')
            result = subprocess.run(['bash', str(SCRIPT), 'plan'], cwd=folder, env=env,
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((folder / 'terraform-was-called').exists())
            self.assertFalse((folder / '.jenkins-run').exists())
            return result

    def test_wrong_account_blocks_before_terraform(self):
        self.assertIn('otra cuenta', self.run_guard(account='999999999999').stderr)

    def test_missing_remote_state_blocks_before_terraform(self):
        self.assertIn('No existe el estado compartido', self.run_guard().stderr)

    def test_s3_api_failure_is_not_treated_as_empty_state(self):
        result = self.run_guard(state_result='', state_exit=1)
        self.assertNotIn('No existe el estado compartido', result.stderr)


class SavedPlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.folder = Path(self.directory.name)
        (self.folder / 'jenkins').mkdir()
        (self.folder / 'static').mkdir()
        for name in ['main.tf', '.terraform.lock.hcl', 'jenkins/backend.tf', 'static/index.html']:
            (self.folder / name).write_text('')
        self.key = self.folder / 'credential.pub'
        self.key.write_text('ssh-ed25519 YOUR_PUBLIC_KEY')
        programs = {
            'git': '#!/bin/bash\nprintf "%s\\n" ' + 'a' * 40 + '\n',
            'aws': '''#!/bin/bash
if [[ "$1" == sts ]]; then echo 123456789012; else
echo '{"Contents": [{"Key": "aws-lab/terraform.tfstate"}]}'
fi
''',
            'terraform': '''#!/bin/bash
printf '%s\\n' "$*" >> terraform-calls
if [[ "$2" == plan ]]; then printf 'saved-plan' > .jenkins-run/deploy.tfplan; fi
''',
        }
        for name, content in programs.items():
            path = self.folder / name
            path.write_text(content)
            path.chmod(0o700)
        self.env = dict(os.environ, PATH=f'{self.folder}:' + os.environ['PATH'],
                        AWS_ACCOUNT_ID='123456789012', STATE_BUCKET='example-state-bucket',
                        STATE_KEY='aws-lab/terraform.tfstate', DEPLOY_COMMIT='a' * 40,
                        SSH_ALLOWED_CIDR='192.0.2.10/32', AWS_DEFAULT_REGION='us-east-1',
                        ALLOW_EMPTY_STATE='false', TF_VAR_ssh_public_key_path=str(self.key))

    def execute(self, mode):
        return subprocess.run(['bash', str(SCRIPT), mode], cwd=self.folder,
                              env=self.env, text=True, capture_output=True)

    def test_apply_uses_saved_plan_after_original_key_binding_disappears(self):
        result = self.execute('plan')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.key.unlink()
        result = self.execute('apply')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.folder / 'terraform-calls').read_text().splitlines()
        self.assertEqual(sum(' plan ' in line for line in calls), 1)
        self.assertEqual(sum(' apply ' in line for line in calls), 1)
        self.assertTrue(any(line.endswith('deploy.tfplan') and ' apply ' in line for line in calls))
        self.assertTrue((self.folder / '.jenkins-run/operator.pub').exists())

    def test_modified_plan_blocks_apply(self):
        result = self.execute('plan')
        self.assertEqual(result.returncode, 0, result.stderr)
        (self.folder / '.jenkins-run/deploy.tfplan').write_text('changed-plan')
        self.assertNotEqual(self.execute('apply').returncode, 0)
        self.assertNotIn(' apply ', (self.folder / 'terraform-calls').read_text())


if __name__ == '__main__':
    unittest.main()
