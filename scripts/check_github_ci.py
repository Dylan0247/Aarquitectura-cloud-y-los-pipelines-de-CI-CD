"""Exige el último intento de Terraform CI exitoso para el commit del checkout."""
import json
import os
import re
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def require_success(runs, sha, repository):
    matches = [run for run in runs if (
        run.get('head_sha') == sha
        and run.get('head_repository', {}).get('full_name') == repository
        and run.get('event') in ('push', 'workflow_dispatch')
        and run.get('head_branch') in ('main', 'git_actions')
        and run.get('path', '').split('@')[0] == '.github/workflows/terraform-ci.yml'
    )]
    if not matches:
        raise ValueError('No hay ejecución de Terraform CI para este commit en main/git_actions. Publica el workflow y espera a que termine.')
    latest = max(matches, key=lambda run: (run['run_number'], run.get('run_attempt', 1)))
    if latest.get('status') != 'completed' or latest.get('conclusion') != 'success':
        raise ValueError('El último intento de Terraform CI no ha terminado correctamente. Revisa GitHub Actions.')
    return latest


def main():
    sha = os.environ.get('DEPLOY_COMMIT', '')
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    if not re.fullmatch(r'[0-9a-f]{40}', sha) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Commit o repositorio inválido.')
    query = urlencode({'head_sha': sha, 'per_page': 100})
    url = f'https://api.github.com/repos/{repository}/actions/workflows/terraform-ci.yml/runs?{query}'
    request = Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'terraform-jenkins-lab'})
    with urlopen(request, timeout=30) as response:
        payload = json.load(response)
    run = require_success(payload.get('workflow_runs', []), sha, repository)
    print(f"Terraform CI correcto para {sha}: ejecución {run['id']}.")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, HTTPError, URLError, TimeoutError, KeyError) as error:
        # No volcar respuestas HTTP ni variables de entorno.
        print(f'No se puede autorizar el despliegue: {error}', file=sys.stderr)
        sys.exit(1)
