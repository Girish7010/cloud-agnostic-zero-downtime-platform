terraform {
  # >= 1.10: S3 native state locking (use_lockfile)
  # >= 1.11: write-only arguments used by modules/aws-stack
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial backend configuration: bucket, region and kms_key_id come from
  # `terraform init -backend-config=backend.hcl` (see backend.hcl.example) so
  # no bucket name or account ID is committed. Unlike infra/live/aws/*, this
  # generic root also takes `key` from backend.hcl, because the same code is
  # reused for different ad-hoc stacks; use one key (and one working dir)
  # per stack_name.
  backend "s3" {
    use_lockfile = true # S3 native locking, no DynamoDB table
    encrypt      = true
  }
}
