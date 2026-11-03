variable "aws_region" {
  description = "AWS region for this environment. EU tenants must use an approved EU region."
  type        = string
}

provider "aws" {
  region = var.aws_region
}
