provider "aws" {
  region = var.aws_region

  # Every resource gets ownership/residency tags even if a module forgets.
  default_tags {
    tags = {
      Project         = "cloud-agnostic-deployment-platform"
      Environment     = var.environment
      ManagedBy       = "Terraform"
      tenant_id       = var.tenant_id
      deployment_mode = var.deployment_mode
      data_residency  = var.data_residency
    }
  }
}
