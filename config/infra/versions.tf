# Pin the provider and keep the CLI constraint aligned with the checked-in Terraform image.
terraform {
  required_version = ">= 1.14.0"

  required_providers {
    github = {
      source  = "integrations/github"
      version = "= 6.12.0"
    }
  }
}
