
terraform {
  required_version = ">= v1.17.0" //comando = terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" // Version del proveedor, independiente de AWS CLI.
    }
  }
}
