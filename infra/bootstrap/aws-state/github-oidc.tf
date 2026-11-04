# -----------------------------------------------------------------------------
# GitHub Actions -> AWS without long-lived keys (OIDC federation).
#
#   plan role   read-only, for `terraform plan` on PRs and the scheduled
#               drift-detection job on main
#   apply role  write, ONLY for jobs running in the GitHub environment
#               "production" (which has required reviewers configured in
#               GitHub settings, so every apply is a human-approved change)
#
# Trust is pinned to one repository via the token's `sub` claim:
#   repo:<owner>/<repo>:ref:refs/heads/main      push / schedule on main
#   repo:<owner>/<repo>:pull_request             pull_request events
#   repo:<owner>/<repo>:environment:production   jobs with `environment: production`
# Forks cannot mint tokens with this repo's sub claim.
# -----------------------------------------------------------------------------

locals {
  repo         = var.github_repository
  oidc_host    = "token.actions.githubusercontent.com"
  state_bucket = aws_s3_bucket.state.arn
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list omitted: AWS validates GitHub's OIDC certificate against
  # its own trusted CA store, and the provider no longer requires it.
}

# ----------------------------------------------------------------- plan role

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values = [
        "repo:${local.repo}:ref:refs/heads/main",
        "repo:${local.repo}:pull_request",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "github-terraform-plan"
  description          = "GitHub Actions: terraform plan / drift detection (read-only)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# AWS-managed ReadOnlyAccess: plan must refresh every resource type the stacks
# manage (EC2, EKS, RDS, ElastiCache, IAM, KMS, logs, ...). It grants no
# write actions and no secretsmanager:GetSecretValue.
resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "plan_extra" {
  statement {
    sid       = "ReadState"
    actions   = ["s3:ListBucket", "s3:GetObject"]
    resources = [local.state_bucket, "${local.state_bucket}/*"]
  }

  # Plan still takes the lock, so it may create/remove *.tflock objects only.
  statement {
    sid       = "StateLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket}/*.tflock"]
  }

  statement {
    sid       = "DecryptState"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }

  # Refreshing aws_secretsmanager_secret_version calls GetSecretValue. Scoped to
  # the Redis AUTH secrets created by modules/aws-stack ("<stack>/redis-auth").
  # The RDS master secret is not readable by this role.
  statement {
    sid       = "RefreshRedisAuthSecretVersion"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:${local.partition}:secretsmanager:*:${local.account_id}:secret:*/redis-auth-*"]
  }
}

resource "aws_iam_role_policy" "plan_extra" {
  name   = "terraform-state-and-refresh"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan_extra.json
}

# ---------------------------------------------------------------- apply role

data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${local.repo}:environment:${var.github_apply_environment}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "github-terraform-apply"
  description        = "GitHub Actions: terraform apply, production environment only"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
  # A full stack (EKS + Multi-AZ RDS + ElastiCache) can take > 1 h to create.
  max_session_duration = 7200
}

data "aws_iam_policy_document" "apply" {
  # Full control of the services the provider layer uses, and nothing else
  # (no Organizations, billing, CloudTrail, S3 other than state, etc.).
  statement {
    sid = "ProviderLayerServices"
    actions = [
      "ec2:*",
      "eks:*",
      "rds:*",
      "elasticache:*",
      "kms:*",
      "logs:*",
      "secretsmanager:*",
      "autoscaling:Describe*",
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
  }

  # IAM is needed for EKS cluster/node/pod-identity roles. This is the
  # privilege-escalation path, so the CI identities and the OIDC trust itself
  # are explicitly protected below. Next step: a permissions boundary that all
  # roles created by Terraform must carry.
  statement {
    sid = "IamForStackRoles"
    actions = [
      "iam:*Role*",
      "iam:*Policy*",
      "iam:*InstanceProfile*",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:CreateServiceLinkedRole",
      "iam:GetOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "ProtectCiIdentities"
    effect = "Deny"
    actions = [
      "iam:*Role*",
      "iam:*Policy*",
      "iam:*OpenIDConnectProvider*",
    ]
    resources = [
      aws_iam_role.plan.arn,
      "arn:${local.partition}:iam::${local.account_id}:role/github-terraform-apply",
      aws_iam_openid_connect_provider.github.arn,
    ]
  }

  # kms:* above must not let CI lock everyone out of the state key.
  statement {
    sid    = "ProtectStateKey"
    effect = "Deny"
    actions = [
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:CreateGrant",
    ]
    resources = [aws_kms_key.state.arn]
  }

  statement {
    sid       = "ReadWriteState"
    actions   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [local.state_bucket, "${local.state_bucket}/*"]
  }

  statement {
    sid       = "EncryptState"
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.state.arn]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
