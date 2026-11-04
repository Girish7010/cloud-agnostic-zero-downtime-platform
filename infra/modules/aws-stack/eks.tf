# -----------------------------------------------------------------------------
# EKS with two managed node groups.
#   system: platform controllers (Argo CD, KEDA, ESO, Prometheus, CoreDNS)
#   app:    API + worker pods; min/max bound the cluster autoscaler
# Node autoscaling: cluster-autoscaler (installed by infra/platform when
# target = "aws") scales the app group between min and max. Managed node
# groups tag their ASGs for autoscaler auto-discovery automatically.
# Karpenter is the documented next step (faster, bin-packing, Spot mix).
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.29"

  name                = local.name
  kubernetes_version  = var.kubernetes_version
  deletion_protection = var.deletion_protection

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint so CI (GitHub-hosted runners) can run the platform layer;
  # authentication is still IAM. Restrict CIDRs where possible; a self-hosted
  # runner inside the VPC would let this become private-only.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.cluster_endpoint_public_cidrs
  endpoint_private_access      = true

  # Access via EKS access entries (no aws-auth ConfigMap). The identity that
  # runs apply (the CI apply role) becomes cluster admin.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true
  access_entries = {
    for i, arn in var.cluster_admin_principal_arns : "admin-${i}" => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Envelope-encrypt Kubernetes Secrets with the stack key instead of letting
  # the community module create a second key.
  create_kms_key = false
  encryption_config = {
    provider_key_arn = aws_kms_key.this.arn
    resources        = ["secrets"]
  }

  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days
  cloudwatch_log_group_kms_key_id        = aws_kms_key.this.arn

  # Pod Identity replaces IRSA for our workloads, so no OIDC provider needed.
  enable_irsa = false

  addons = {
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
  }

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.system_node_instance_types
      min_size       = var.system_node_count
      desired_size   = var.system_node_count
      max_size       = var.system_node_count + 1
      labels         = { "node-role" = "system" }
    }

    app = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.app_node_instance_types
      min_size       = var.app_node_min_size
      # desired_size is only the initial value; the module ignores later
      # changes so the cluster autoscaler owns it after creation.
      desired_size = var.app_node_min_size
      max_size     = var.app_node_max_size
      labels       = { "node-role" = "app" }
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# EKS Pod Identity roles for in-cluster controllers.
# -----------------------------------------------------------------------------

# External Secrets Operator: read-only access to THIS stack's secrets only
# (the RDS-managed master secret and the Redis AUTH secret) plus decrypt with
# THIS stack's key. Hand-written so the scope is obvious in review.
data "aws_iam_policy_document" "eso_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_read" {
  statement {
    sid     = "ReadThisStacksSecrets"
    actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [
      aws_db_instance.this.master_user_secret[0].secret_arn,
      aws_secretsmanager_secret.redis_auth.arn,
    ]
  }

  statement {
    sid       = "DecryptWithThisStacksKey"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_role" "eso" {
  name               = "${local.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.eso_trust.json
  tags               = local.tags
}

resource "aws_iam_role_policy" "eso" {
  name   = "read-stack-secrets"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_read.json
}

# Must match the namespace/service account used by the external-secrets Helm
# release in infra/platform.
resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = module.eks.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso.arn
  tags            = local.tags
}

# AWS Load Balancer Controller and cluster-autoscaler have long, AWS-maintained
# policies; the community module ships them, so we do not copy them by hand.
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                            = "${local.name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }

  tags = local.tags
}

module "cluster_autoscaler_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 2.10"

  name                             = "${local.name}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  # Scopes the write actions to ASGs tagged for this cluster only.
  cluster_autoscaler_cluster_names = [module.eks.cluster_name]

  associations = {
    this = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "cluster-autoscaler"
    }
  }

  tags = local.tags
}
