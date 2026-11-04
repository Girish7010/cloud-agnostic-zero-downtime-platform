terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Chicken-and-egg: this root CREATES the remote state bucket, so it cannot
  # store its own state there on first run. It uses local state
  # (terraform.tfstate, gitignored). It holds no secrets: only bucket, key and
  # role definitions. Keep the file safe (or, after the first apply, migrate it
  # into the bucket with a `backend "s3"` block + `terraform init -migrate-state`).
  # Losing it is recoverable with `terraform import`.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "cloud-agnostic-deployment-platform"
      ManagedBy = "Terraform"
      Layer     = "bootstrap"
    }
  }
}
