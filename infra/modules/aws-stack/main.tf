# -----------------------------------------------------------------------------
# aws-stack: the AWS implementation of the provider layer.
#
# One instance of this module = one isolated stack (VPC, EKS, PostgreSQL,
# Redis-compatible queue, KMS key, secrets). The shared multi-tenant stack and
# every dedicated tenant stack are instances of this same module; they differ
# only in inputs (see infra/live/aws/*).
#
# The module does NOT configure the aws provider. The calling root does, so the
# region is fixed by the root and checked here (residency enforcement, part 2).
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  # Exclude Local Zones / Wavelength zones; we want the region's standard AZs.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = var.stack_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  # Residency and ownership tags on every resource (the calling root also sets
  # them as provider default_tags; setting them here keeps the module correct
  # when used from a root that forgets).
  tags = merge(var.tags, {
    stack_name      = var.stack_name
    tenant_id       = var.tenant_id
    deployment_mode = var.deployment_mode
    data_residency  = var.data_residency
    managed_by      = "terraform"
  })
}

# -----------------------------------------------------------------------------
# KMS: one customer-managed key per stack. Encrypts EKS secrets, RDS storage,
# Performance Insights, the RDS master secret, ElastiCache at rest, the Redis
# AUTH secret and CloudWatch log groups. Per-stack keys mean a dedicated
# tenant's data can be crypto-shredded independently of other tenants.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  # Default key policy: delegate access control to IAM in this account.
  statement {
    sid       = "AccountRootFullAccess"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs is not an IAM principal in the account, so it must be
  # allowed explicitly, and only for log groups in this account and region.
  statement {
    sid = "CloudWatchLogsUse"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "this" {
  description             = "${local.name}: encryption key for EKS secrets, RDS, ElastiCache, Secrets Manager and logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
  tags                    = local.tags

  lifecycle {
    # Residency enforcement, part 2: the variable validation only checks the
    # *declared* region. This checks the region the aws provider is actually
    # configured for, so a root cannot say region = "eu-central-1" while its
    # provider points at us-east-1. Both inputs are data sources read during
    # plan, so a mismatch fails `terraform plan` and nothing is created.
    precondition {
      condition     = data.aws_region.current.region == var.region
      error_message = "The aws provider region (${data.aws_region.current.region}) does not match var.region (${var.region})."
    }

    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= 3
      error_message = "Region ${var.region} has fewer than 3 standard AZs; this module requires 3."
    }
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}
