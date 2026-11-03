# Provider-layer starter only. Add reviewed modules for VPC, EKS, RDS,
# ElastiCache, ECR, IAM and Secrets Manager before applying.
# No billable infrastructure is created by this file.
locals {
  common_tags = {
    Project     = "cloud-agnostic-deployment-platform"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
