# -----------------------------------------------------------------------------
# Dedicated stack for tenant "acme" (example), EU residency, Ireland.
#
# NEW DEDICATED TENANT = ONE REVIEWED CHANGE:
#   1. cp -r infra/live/aws/dedicated-acme-eu infra/live/aws/dedicated-<tenant>-<eu|us>
#   2. edit the `locals` block below (tenant, region, CIDR, size)
#   3. change `key` in versions.tf to aws/dedicated-<tenant>-<eu|us>/terraform.tfstate
#   4. add the tenant's GitOps values (see infra/tenants/README.md)
# Everything else (network, cluster, data stores, encryption, residency checks)
# comes from the same modules/aws-stack used by the shared stack.
# A wrong pairing such as data_residency = "eu" with a us-* region fails
# `terraform plan` (variable validation in modules/aws-stack).
# -----------------------------------------------------------------------------

locals {
  tenant_id      = "acme"
  data_residency = "eu"
  region         = "eu-west-1"
  vpc_cidr       = "10.41.0.0/16" # unique per stack so stacks can be peered later

  # Sizing profile "dedicated-small": the tenant's share of load, not the
  # whole platform peak. Scale up by editing these values.
  app_node_min_size = 2
  app_node_max_size = 6
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project         = "cloud-agnostic-deployment-platform"
      ManagedBy       = "Terraform"
      tenant_id       = local.tenant_id
      deployment_mode = "dedicated"
      data_residency  = local.data_residency
    }
  }
}

module "stack" {
  source = "../../../modules/aws-stack"

  stack_name      = "${local.tenant_id}-${local.data_residency}"
  tenant_id       = local.tenant_id
  deployment_mode = "dedicated"
  data_residency  = local.data_residency
  region          = local.region

  vpc_cidr           = local.vpc_cidr
  single_nat_gateway = false

  # TODO before apply: restrict to CI runner / admin egress ranges.
  cluster_endpoint_public_cidrs = ["0.0.0.0/0"]

  system_node_instance_types = ["m6i.large"]
  system_node_count          = 2
  app_node_instance_types    = ["m6i.large"]
  app_node_min_size          = local.app_node_min_size
  app_node_max_size          = local.app_node_max_size

  postgres_instance_class  = "db.m6g.large"
  postgres_multi_az        = true
  postgres_max_connections = 200
  redis_node_type          = "cache.m7g.large"

  deletion_protection = true
}
