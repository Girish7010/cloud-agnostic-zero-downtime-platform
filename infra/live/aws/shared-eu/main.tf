# -----------------------------------------------------------------------------
# Shared multi-tenant stack, EU (Frankfurt). Hosts every tenant that does not
# need a dedicated stack. EU residency: region and backups stay in eu-central-1.
#
# Sizing assumptions (the app is a black box; replace with measured numbers
# from tests/load once the real image is load-tested):
#   API      150 rps baseline, 2,250 rps peak. Assume ~150 rps per pod at a
#            500m CPU request  -> 15 pods at peak, ~20 with 30% headroom;
#            min 3 (one per AZ). HPA/KEDA scales pods, not Terraform.
#   Worker   20,000 jobs/h = ~5.6 jobs/s. Assume ~1 job/s per worker pod
#            -> 6 pods, KEDA scales on Redis Streams consumer-group lag (see capacity plan in docs/architecture.md: ~72 workers at peak if avg job is 10 s).
#   Nodes    peak ~ (20 + 10) pods x 0.5 vCPU = 15 vCPU of requests
#            -> 5-6 m6i.xlarge (≈3.9 allocatable vCPU each) incl. DaemonSets;
#            min 3 (AZ spread), max 12 (2x margin, also the spend cap).
#   Postgres db.r6g.large (2 vCPU / 16 GiB), Multi-AZ. max_connections 400
#            = 20 API x 10 + 10 workers x 5 + headroom (see module variable).
#   Queue    cache.r7g.large x2 (13 GiB): a 20k jobs/h backlog of even 10 KB
#            jobs is ~200 MB, so memory is ample; r7g is for network/CPU.
#
# Rough monthly cost, eu-central-1 on-demand (approximate list prices, verify
# in the AWS Pricing Calculator before committing to a number):
#   EKS control plane ~$75 | system nodes 2x m6i.large ~$170
#   app nodes 3..12 x m6i.xlarge ~$500 .. ~$2,000
#   RDS r6g.large Multi-AZ + 100 GB gp3 ~$450 | Valkey r7g.large x2 ~$370
#   3 NAT gateways ~$120 + data | CloudWatch logs/metrics ~$100-300
#   => steady ~$1.9k, at max node count ~$3.5k: inside the $9k steady /
#      $16k peak budget, leaving room for dedicated tenant stacks.
# -----------------------------------------------------------------------------

locals {
  region = "eu-central-1"
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project         = "cloud-agnostic-deployment-platform"
      ManagedBy       = "Terraform"
      tenant_id       = "shared"
      deployment_mode = "shared"
      data_residency  = "eu"
    }
  }
}

module "stack" {
  source = "../../../modules/aws-stack"

  stack_name      = "shared-eu"
  tenant_id       = "shared"
  deployment_mode = "shared"
  data_residency  = "eu"
  region          = local.region

  vpc_cidr           = "10.40.0.0/16"
  single_nat_gateway = false # production: one NAT per AZ

  # TODO before apply: restrict to the CI runner / admin egress ranges.
  # GitHub-hosted runner IPs are not stable, hence the open default; access
  # still requires an IAM identity with an EKS access entry.
  cluster_endpoint_public_cidrs = ["0.0.0.0/0"]

  system_node_instance_types = ["m6i.large"]
  system_node_count          = 2
  app_node_instance_types    = ["m6i.xlarge"]
  app_node_min_size          = 3
  app_node_max_size          = 12

  postgres_instance_class        = "db.r6g.large"
  postgres_multi_az              = true
  postgres_allocated_storage_gb  = 100
  postgres_max_connections       = 400
  postgres_backup_retention_days = 14

  redis_node_type          = "cache.r7g.large"
  redis_num_cache_clusters = 2

  deletion_protection = true
  log_retention_days  = 30
}
