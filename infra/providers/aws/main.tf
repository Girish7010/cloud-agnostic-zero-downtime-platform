# Thin wrapper: the provider layer itself is modules/aws-stack.
# Defaults here are nonprod-sized (single NAT, single-AZ RDS, small nodes).
module "stack" {
  source = "../../modules/aws-stack"

  stack_name      = var.stack_name
  tenant_id       = var.tenant_id
  deployment_mode = var.deployment_mode
  data_residency  = var.data_residency
  region          = var.aws_region

  vpc_cidr                      = var.vpc_cidr
  single_nat_gateway            = var.single_nat_gateway
  cluster_endpoint_public_cidrs = var.cluster_endpoint_public_cidrs

  system_node_instance_types = ["t3.large"]
  system_node_count          = 2
  app_node_instance_types    = ["t3.xlarge"]
  app_node_min_size          = 1
  app_node_max_size          = 3

  postgres_instance_class  = "db.t4g.medium"
  postgres_multi_az        = var.postgres_multi_az
  postgres_max_connections = 150
  redis_node_type          = "cache.t4g.small"
  deletion_protection      = var.deletion_protection
  log_retention_days       = 7

  tags = { Environment = var.environment }
}
