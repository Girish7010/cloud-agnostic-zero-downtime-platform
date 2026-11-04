variable "region" {
  description = "Region of the state bucket. EU so state about EU tenants stays in the EU."
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state, e.g. <org>-tfstate-<account-id>. Not committed: pass with -var or TF_VAR_state_bucket_name."
  type        = string
}

variable "github_repository" {
  description = "owner/repo allowed to assume the CI roles via GitHub OIDC."
  type        = string
  default     = "Girish7010/cloud-agnostic-zero-downtime-platform"
}

variable "github_apply_environment" {
  description = "GitHub environment (with required reviewers) whose jobs may assume the apply role."
  type        = string
  default     = "production"
}

variable "noncurrent_version_retention_days" {
  description = "How long old state versions are kept (rollback/forensics)."
  type        = number
  default     = 90
}
