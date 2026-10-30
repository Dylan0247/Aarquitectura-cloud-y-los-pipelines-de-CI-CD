pipeline {
    agent any
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 90, unit: 'MINUTES')
    }
    parameters {
        booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Generar un plan en AWS y, tras aprobación, aplicarlo.')
        booleanParam(name: 'ALLOW_EMPTY_STATE', defaultValue: false, description: 'Solo para infraestructura nueva: permitir un estado remoto que aún no existe. No usar para recursos existentes.')
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '', description: 'Cuenta AWS esperada (12 dígitos). Obligatoria para DEPLOY.')
        string(name: 'STATE_BUCKET', defaultValue: '', description: 'Bucket privado existente para el estado de Terraform.')
        string(name: 'STATE_KEY', defaultValue: 'aws-lab/terraform.tfstate', description: 'Clave del estado compartido con WSL.')
        string(name: 'SSH_ALLOWED_CIDR', defaultValue: '', description: 'IPv4 pública del operador con /32.')
    }
    environment {
        TF_IN_AUTOMATION = 'true'
        TF_INPUT = 'false'
        AWS_EC2_METADATA_DISABLED = 'true'
        AWS_DEFAULT_REGION = 'us-east-1'
        AWS_PROFILE = 'default'
        GITHUB_REPOSITORY = 'Dylan0247/Aarquitectura-cloud-y-los-pipelines-de-CI-CD'
    }
    stages {
        stage('Checkout') {
            steps {
                deleteDir()
                checkout scm
                script {
                    env.DEPLOY_COMMIT = sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
                }
            }
        }
        stage('Validar Terraform') {
            steps {
                sh '''#!/bin/bash
set -euo pipefail
terraform fmt -check -recursive
terraform init -backend=false -input=false -lockfile=readonly -no-color
terraform validate -no-color
python3 -m unittest discover -s tests -p 'test_*.py'
'''
            }
        }
        stage('Verificar GitHub Actions') {
            when { expression { params.DEPLOY } }
            steps { sh 'python3 scripts/check_github_ci.py' }
        }
        stage('Plan de despliegue') {
            when { expression { params.DEPLOY } }
            steps {
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    string(credentialsId: 'rds-db-password', variable: 'TF_VAR_db_password'),
                    file(credentialsId: 'terraform-ssh-public-key', variable: 'TF_VAR_ssh_public_key_path')
                ]) {
                    sh 'bash scripts/jenkins_terraform.sh plan'
                }
            }
        }
        stage('Aprobar y aplicar el plan') {
            when { expression { params.DEPLOY } }
            steps {
                timeout(time: 20, unit: 'MINUTES') {
                    input message: "Revisa el plan de ${env.DEPLOY_COMMIT} y la cuenta ${params.AWS_ACCOUNT_ID}. ¿Aplicarlo?", ok: 'Aplicar este plan'
                }
                withCredentials([
                    file(credentialsId: 'aws-academy-credentials', variable: 'AWS_SHARED_CREDENTIALS_FILE'),
                    string(credentialsId: 'rds-db-password', variable: 'TF_VAR_db_password'),
                    file(credentialsId: 'terraform-ssh-public-key', variable: 'TF_VAR_ssh_public_key_path')
                ]) {
                    sh 'bash scripts/jenkins_terraform.sh apply'
                }
            }
        }
    }
    post {
        always {
            deleteDir()
        }
    }
}
