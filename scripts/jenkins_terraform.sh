#!/bin/bash
set -euo pipefail
umask 077

mode="${1:?Usa plan o apply}"
[[ "$mode" == plan || "$mode" == apply ]] || exit 1
[[ "${AWS_ACCOUNT_ID:-}" =~ ^[0-9]{12}$ ]] || { echo 'Falta una cuenta AWS válida.' >&2; exit 1; }
[[ "${STATE_BUCKET:-}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || { echo 'Falta un bucket de estado válido.' >&2; exit 1; }
[[ -n "${STATE_KEY:-}" && "$STATE_KEY" != /* ]] || { echo 'Falta una clave de estado relativa.' >&2; exit 1; }
[[ "${DEPLOY_COMMIT:-}" == "$(git rev-parse HEAD)" ]] || { echo 'El checkout ha cambiado.' >&2; exit 1; }

actual_account="$(aws sts get-caller-identity --query Account --output text)"
[[ "$actual_account" == "$AWS_ACCOUNT_ID" ]] || { echo 'Las credenciales pertenecen a otra cuenta AWS.' >&2; exit 1; }
export TF_VAR_ssh_allowed_cidr="${SSH_ALLOWED_CIDR:?Indica la IPv4 del operador con /32}"
export TF_VAR_aws_region="$AWS_DEFAULT_REGION"

if [[ "$mode" == plan ]]; then
    python3 - <<'PY'
import ipaddress, os
cidr = ipaddress.IPv4Network(os.environ['TF_VAR_ssh_allowed_cidr'])
if cidr.prefixlen != 32 or cidr.network_address == ipaddress.IPv4Address('0.0.0.0'):
    raise SystemExit('SSH requiere una IPv4 con /32.')
PY
    # No convertir un error de permisos o conexión en un estado vacío.
    existing="$(aws s3api list-objects-v2 --bucket "$STATE_BUCKET" --prefix "$STATE_KEY" --output json |
        python3 -c 'import json,os,sys; print(any(x["Key"] == os.environ["STATE_KEY"] for x in json.load(sys.stdin).get("Contents", [])))')"
    if [[ "$existing" != True && "${ALLOW_EMPTY_STATE:-false}" != true ]]; then
        echo 'No existe el estado compartido. Migra primero el estado de WSL; para infraestructura nueva usa ALLOW_EMPTY_STATE.' >&2
        exit 1
    fi
    mkdir -m 700 .jenkins-run
    cp ./*.tf .terraform.lock.hcl .jenkins-run/
    cp jenkins/backend.tf .jenkins-run/backend.tf
    cp -R static .jenkins-run/static
    cp "$TF_VAR_ssh_public_key_path" .jenkins-run/operator.pub
    export TF_VAR_ssh_public_key_path="$PWD/.jenkins-run/operator.pub"
    terraform -chdir=.jenkins-run init -input=false -lockfile=readonly -no-color \
        -backend-config="bucket=$STATE_BUCKET" -backend-config="key=$STATE_KEY" \
        -backend-config="region=$AWS_DEFAULT_REGION"
    terraform -chdir=.jenkins-run validate -no-color
    terraform -chdir=.jenkins-run plan -input=false -lock-timeout=5m -no-color -out=deploy.tfplan
    sha256sum .jenkins-run/deploy.tfplan > .jenkins-run/plan.sha256
else
    export TF_VAR_ssh_public_key_path="$PWD/.jenkins-run/operator.pub"
    sha256sum -c .jenkins-run/plan.sha256
    terraform -chdir=.jenkins-run apply -input=false -lock-timeout=5m -no-color deploy.tfplan
    terraform -chdir=.jenkins-run output -raw alb_url
fi
