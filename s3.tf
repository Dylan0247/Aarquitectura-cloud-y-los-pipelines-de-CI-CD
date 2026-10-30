// Almacenamiento de archivos estaticos con nombre unico generado por AWS provider.
resource "aws_s3_bucket" "static" {
  bucket_prefix = "project-static-"
  force_destroy = false // Protege archivos subidos manualmente al borrar el proyecto.
}

// El propietario del bucket controla los objetos; no se utilizan ACL.
resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

// Terraform gestiona este archivo de ejemplo, incluido su borrado.
resource "aws_s3_object" "index" {
  bucket                 = aws_s3_bucket.static.id
  key                    = "index.html"
  source                 = "${path.module}/static/index.html"
  source_hash            = filemd5("${path.module}/static/index.html")
  content_type           = "text/html; charset=utf-8"
  server_side_encryption = "AES256"

  depends_on = [
    aws_s3_bucket_ownership_controls.static,
    aws_s3_bucket_public_access_block.static,
    aws_s3_bucket_server_side_encryption_configuration.static
  ]
}
