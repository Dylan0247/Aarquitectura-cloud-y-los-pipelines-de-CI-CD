// Plantilla copiada al directorio de despliegue; no cambia el backend de la raíz.
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
