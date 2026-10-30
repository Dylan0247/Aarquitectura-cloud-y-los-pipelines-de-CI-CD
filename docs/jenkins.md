# Despliegue con Jenkins

El [Jenkinsfile](../Jenkinsfile) valida Terraform y, con `DEPLOY` activado, exige CI correcta del mismo commit, prepara un plan, espera aprobación y aplica ese plan. La instalación Docker es local; no crea recursos AWS al arrancar.

## 1. Arrancar Jenkins local

Desde la raíz del proyecto, con Docker Desktop en modo Linux:

```bash
docker compose -f jenkins/compose.yaml up -d --build
```

Abre [Jenkins local](http://localhost:8080). El puerto se publica solo en `127.0.0.1`. La imagen incorpora Terraform 1.17.0, AWS CLI, Python y los plugins del pipeline. Jenkins, sus credenciales y su configuración persisten en el volumen `jenkins_home`; el proyecto y las credenciales de WSL no se montan en el contenedor. La imagen base LTS, AWS CLI y los plugins se resuelven al construir; Terraform está fijado y se verifica contra el checksum de HashiCorp.

Para desbloquear la instalación, consulta la contraseña **en tu terminal**, sin pegarla en el chat ni en el repositorio:

```bash
docker compose -f jenkins/compose.yaml exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Completa el asistente y crea tu usuario administrador. Los plugins necesarios ya se incluyen en la imagen. Para este laboratorio local, configura **Manage Jenkins → Nodes → Built-In Node → Configure** con un executor. Ejecuta únicamente este repositorio de confianza. No configures jobs de pull requests de terceros en este controlador.

```bash
docker compose -f jenkins/compose.yaml stop
docker compose -f jenkins/compose.yaml start
```

`stop` conserva los datos. No uses `down -v` para parar Jenkins: eliminaría su volumen.

## 2. Crear el job

En la instalación preparada durante esta sesión ya existe el job `aws-terraform`, apuntando a `git_actions`, sin builds iniciados. Los pasos siguientes permiten revisarlo o recrearlo en otra instalación.

Los archivos deben estar publicados y la CI del commit debe haber terminado correctamente antes de desplegar. La preparación local de este pipeline no hace commit ni push.

1. **New Item → Pipeline**, nombre `aws-terraform`.
2. **Definition → Pipeline script from SCM → Git**.
3. Repository URL: `https://github.com/Dylan0247/Aarquitectura-cloud-y-los-pipelines-de-CI-CD.git`.
4. Branch Specifier: `*/git_actions` (o `*/main` cuando los cambios estén allí).
5. Script Path: `Jenkinsfile`. Guarda y ejecuta **Build Now** una vez para registrar los parámetros y validar, sin despliegue.
6. Después usa **Build with Parameters**.

El job no tiene webhook ni polling configurados: se inicia manualmente. Solo `DEPLOY=true` consulta AWS. El control de CI consulta la API pública de GitHub sin token; un error, un límite de API o una ejecución aún pendiente bloquean el despliegue. Exige el último intento de `terraform-ci.yml` para el SHA exacto, en `main` o `git_actions`, disparado por push o ejecución manual. Una CI de otro commit, workflow o fork no lo autoriza.

## 3. Credenciales de Jenkins

En **Manage Jenkins → Credentials**, crea las siguientes credenciales para el job de confianza. Nunca añadas estos archivos ni sus valores a Git.

| ID | Tipo | Contenido |
| --- | --- | --- |
| `aws-academy-credentials` | Secret file | Archivo INI con perfil `[default]`, `aws_access_key_id`, `aws_secret_access_key` y `aws_session_token` actuales de Academy. |
| `rds-db-password` | Secret text | Contraseña de RDS. Si ya existe la base, conserva la misma contraseña para evitar cambios no deseados. |
| `terraform-ssh-public-key` | Secret file | Tu clave pública OpenSSH `.pub`, nunca la privada. Para recursos existentes usa la misma pública. |

El archivo AWS usa el mismo formato ficticio documentado en el README. Cuando Academy renueve las credenciales, actualiza el Secret file; Jenkins no hereda el archivo de WSL. Las credenciales se vuelven a cargar después de la aprobación, y se verifica otra vez la cuenta antes del apply. Si han caducado, actualízalas antes de continuar; un error no crea un plan nuevo ni aplica otro distinto.

## 4. Estado remoto compartido

Necesitas un bucket S3 **dedicado al estado**, privado, con versionado, cifrado y bloqueo de acceso público. Créalo fuera de este stack con consola o el procedimiento autorizado del laboratorio. El bucket `s3.tf` sirve para `index.html`; no lo uses como backend del mismo stack.

Permisos del backend: `s3:ListBucket` sobre el bucket; `s3:GetObject` y `s3:PutObject` sobre la clave de estado; y `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` sobre su archivo `.tflock`. Los permisos de creación de recursos del stack son adicionales. El pipeline activa el bloqueo nativo de S3 con `use_lockfile = true`.

Si ya desplegaste con WSL, **migra desde la carpeta que contiene el estado real** antes de usar Jenkins. Esta copia de Windows no contiene un estado local: eso no demuestra que AWS esté vacío. No ejecutes dos estados independientes sobre los mismos recursos.

En WSL, con credenciales vigentes y sin otros procesos Terraform:

```bash
# Desde la carpeta que contiene el estado real y esta configuración.
terraform state list
# Guarda una copia privada antes de migrar, fuera del repositorio.
backup_dir="$(mktemp -d "$HOME/terraform-state-backup.XXXXXX")"
chmod 700 "$backup_dir"
(umask 077; terraform state pull > "$backup_dir/terraform.tfstate")

# Esta plantilla local está ignorada por Git.
cp jenkins/backend.tf backend.local.tf
read -rp 'Bucket de estado existente: ' STATE_BUCKET
read -rp 'Clave del estado (ej. aws-lab/terraform.tfstate): ' STATE_KEY
terraform init -migrate-state \
  -backend-config="bucket=$STATE_BUCKET" \
  -backend-config="key=$STATE_KEY" \
  -backend-config="region=us-east-1"
terraform state list
```

Revisa la migración y confirma únicamente el traslado al bucket elegido. Contrasta la lista de recursos antes/después. Conserva la copia privada y usa a partir de entonces el mismo bucket y clave en WSL y Jenkins. No publiques estados, planes ni `.terraform/`.

Para infraestructura completamente nueva, sin recursos existentes gestionados por este proyecto, puedes activar `ALLOW_EMPTY_STATE` en el primer despliegue. Por defecto se exige un estado remoto existente para evitar recrear infraestructura cuyo estado quedó en WSL. Un estado remoto vacío o una clave equivocada requieren revisión del operador: esta comprobación no puede descubrir todos los recursos de la cuenta.

## 5. Planificar y desplegar

En **Build with Parameters**:

| Parámetro | Valor |
| --- | --- |
| `DEPLOY` | Actívalo para plan y apply; desactivado solo valida. |
| `AWS_ACCOUNT_ID` | Cuenta de Academy esperada, 12 dígitos. Se compara con STS. |
| `STATE_BUCKET` | Bucket privado del paso anterior. |
| `STATE_KEY` | Clave exacta compartida con WSL. Predeterminada: `aws-lab/terraform.tfstate`. |
| `SSH_ALLOWED_CIDR` | Tu IPv4 pública `/32`, no la IP del contenedor. |
| `ALLOW_EMPTY_STATE` | Desactivado salvo primer despliegue de infraestructura nueva. |

El pipeline usa `us-east-1`, crea una copia temporal con backend S3 en `.jenkins-run/` y guarda allí un plan privado. Revisa **Console Output**: recursos que se crearán, modificarán o destruirán, cuenta, bucket, clave y SHA. Cuando llegue la aprobación, pulsa **Aplicar este plan** únicamente si corresponde al despliegue esperado. La aprobación caduca a los 20 minutos; la ejecución completa tiene un límite de 90 minutos.

Solo usuarios autorizados del job deben poder iniciarlo, leer sus logs y aprobarlo. El plan puede mostrar metadatos de infraestructura; Jenkins oculta los atributos sensibles que Terraform marca como tales. El plan binario no se publica como artefacto. Se verifica su checksum y se aplica el mismo archivo; Terraform rechaza un plan obsoleto si cambió el estado. Las ejecuciones del mismo job se serializan; el backend bloquea operaciones concurrentes sobre la misma clave. No crees jobs duplicados sobre este entorno.

Al terminar o fallar se limpia el workspace. El estado permanece en S3. El job no ejecuta `destroy`: para borrar, usa WSL con el backend compartido, las mismas variables y el procedimiento del README. Tras un fallo o timeout revisa el estado y los recursos antes de repetir; no fuerces desbloqueos ni borres el estado.

## Verificación local

```bash
docker compose -f jenkins/compose.yaml config --quiet
bash -n scripts/jenkins_terraform.sh
python3 -m unittest discover -s tests -v
terraform fmt -check -recursive
terraform init -backend=false -input=false -lockfile=readonly
terraform validate
```

Referencias: [instalación Docker de Jenkins](https://www.jenkins.io/doc/book/installing/docker/), [sintaxis del pipeline](https://www.jenkins.io/doc/book/pipeline/syntax/), [backend S3 de Terraform](https://developer.hashicorp.com/terraform/language/backend/s3) y [ejecuciones de GitHub Actions](https://docs.github.com/en/rest/actions/workflow-runs).
