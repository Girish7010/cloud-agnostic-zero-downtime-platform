# -----------------------------------------------------------------------------
# VPC across 3 AZs.
#   private  /19 x3  EKS nodes and pods (VPC CNI gives every pod a VPC IP,
#                    so these are deliberately large: ~8k IPs per AZ)
#   public   /24 x3  NAT gateways and internet-facing load balancers only
#   database /24 x3  RDS + ElastiCache, no route to the internet
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 3, i)]       # 10.x.0.0/19, .32.0/19, .64.0/19
  public_subnets   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 96 + i)]  # 10.x.96.0/24 ...
  database_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 100 + i)] # 10.x.100.0/24 ...

  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  # Data tier has no internet route at all (no NAT, no IGW).
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags the AWS Load Balancer Controller uses to discover subnets.
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = local.tags
}
