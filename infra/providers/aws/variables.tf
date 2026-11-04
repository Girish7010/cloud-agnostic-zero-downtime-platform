# Generic AWS root: everything is an input so the same code can stand up an
# ad-hoc / nonprod stack from a tfvars file. Reviewed production stacks live
# in infra/live/aws/<stack>/ with their values in code.
# Validation of deployment_mode, data_residency and region<->residency happens
# inside modules/aws-stack; it is not duplicated here.

variable "environment" {
  type        = string
  description = "Environment name (tag only)."
  default     = "dev"
}

variable "aws_region" {
  type        = string
  description = "AWS region for this stack. EU tenants must use an eu-* region (enforced by modules/aws-stack)."
}

variable "stack_name" {
  type        = string
  description = "Unique stack name, e.g. dev-eu."
}

variable "tenant_id" {
  type        = string
  description = "Tenant ID, or \"shared\"."
  default     = "shared"
}

variable "deployment_mode" {
  type        = string
  description = "shared | dedicated"
  default     = "shared"
}

variable "data_residency" {
  type        = string
  description = "eu | us"
  default     = "eu"
}

variable "vpc_cidr" {
  type        = string
  description = "VPC IPv4 CIDR (/16)."
  default     = "10.40.0.0/16"
}

variable "single_nat_gateway" {
  type        = bool
  description = "One NAT gateway instead of one per AZ (nonprod cost saving)."
  default     = true
}

variable "cluster_endpoint_public_cidrs" {
  type        = list(string)
  description = "CIDRs allowed to reach the EKS public API endpoint."
}

variable "postgres_multi_az" {
  type        = bool
  description = "RDS Multi-AZ standby."
  default     = false
}

variable "deletion_protection" {
  type        = bool
  description = "Deletion protection on RDS/EKS. Nonprod default false so the stack can be torn down."
  default     = false
}
