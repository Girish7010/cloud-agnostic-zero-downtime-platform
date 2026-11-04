# -----------------------------------------------------------------------------
# Identity of the stack
# -----------------------------------------------------------------------------

variable "stack_name" {
  description = "Unique, short name of this stack (used as a prefix for every resource). Example: shared-eu, acme-eu."
  type        = string

  validation {
    # RDS/ElastiCache identifiers must be lowercase, start with a letter and the
    # ElastiCache replication group id is capped at 40 chars ("<stack>-redis").
    condition     = can(regex("^[a-z][a-z0-9-]{1,32}$", var.stack_name))
    error_message = "stack_name must be 2-33 chars, lowercase letters, digits and dashes, starting with a letter."
  }
}

variable "tenant_id" {
  description = "Tenant identifier. Use \"shared\" for the multi-tenant shared stack."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,32}$", var.tenant_id))
    error_message = "tenant_id must be 2-32 chars of lowercase letters, digits and dashes."
  }
}

variable "deployment_mode" {
  description = "shared = one stack hosting many tenants; dedicated = one stack per tenant."
  type        = string

  validation {
    condition     = contains(["shared", "dedicated"], var.deployment_mode)
    error_message = "deployment_mode must be \"shared\" or \"dedicated\"."
  }
}

variable "data_residency" {
  description = "Where tenant data must stay. \"eu\" forces an eu-* region (see validation on var.region)."
  type        = string

  validation {
    condition     = contains(["eu", "us"], var.data_residency)
    error_message = "data_residency must be \"eu\" or \"us\"."
  }
}

variable "region" {
  description = "AWS region of this stack. Must match the region the calling root configured on its aws provider."
  type        = string

  # Residency enforcement, part 1: a static rule that fails at plan time,
  # before any API call. Cross-variable validation needs Terraform >= 1.9.
  validation {
    condition     = var.data_residency != "eu" || startswith(var.region, "eu-")
    error_message = "data_residency = \"eu\" requires an EU region (eu-*). EU tenant data must not leave the EU."
  }

  validation {
    condition     = var.data_residency != "us" || startswith(var.region, "us-")
    error_message = "data_residency = \"us\" requires a us-* region."
  }
}

variable "tags" {
  description = "Extra tags merged onto every resource."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "VPC CIDR. Must be a /16: subnets are carved with cidrsubnet() offsets that assume it."
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid IPv4 /16."
  }
}

variable "single_nat_gateway" {
  description = "true = one NAT gateway for all AZs (cheaper, nonprod only: an AZ outage cuts egress). false = one NAT per AZ."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Kubernetes (EKS)
# -----------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "EKS control plane version. Check supported versions with `aws eks describe-cluster-versions` before changing."
  type        = string
  default     = "1.35"
}

variable "cluster_endpoint_public_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (IAM auth still required). Restrict to CI runner / office egress IPs."
  type        = list(string)
}

variable "cluster_admin_principal_arns" {
  description = "Extra IAM role/user ARNs granted cluster-admin through EKS access entries (the identity running apply is added automatically)."
  type        = list(string)
  default     = []
}

variable "system_node_instance_types" {
  description = "Instance types for the system node group (CoreDNS, Argo CD, Prometheus, controllers)."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_count" {
  description = "Min/desired size of the system node group (max = this + 1)."
  type        = number
  default     = 2
}

variable "app_node_instance_types" {
  description = "Instance types for the application node group (API + worker pods). x86_64 because the app image architecture is not known to be multi-arch."
  type        = list(string)
  default     = ["m6i.xlarge"]
}

variable "app_node_min_size" {
  description = "Minimum app nodes (baseline load + one AZ of headroom)."
  type        = number
  default     = 3
}

variable "app_node_max_size" {
  description = "Maximum app nodes the cluster autoscaler may scale to (peak load). Caps spend."
  type        = number
  default     = 12
}

# -----------------------------------------------------------------------------
# PostgreSQL (RDS)
# -----------------------------------------------------------------------------

variable "postgres_engine_version" {
  description = "PostgreSQL major (or major.minor) version. \"16\" lets RDS pick the latest 16.x minor."
  type        = string
  default     = "16"
}

variable "postgres_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "postgres_allocated_storage_gb" {
  description = "Initial gp3 storage in GiB. Storage autoscaling grows it up to 5x this value."
  type        = number
  default     = 100
}

variable "postgres_multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover. Keep true for anything holding tenant data."
  type        = bool
  default     = true
}

variable "postgres_max_connections" {
  description = <<-EOT
    max_connections for the parameter group. RDS default is LEAST(RAM/9531392, 5000),
    i.e. ~1,700 on a 16 GiB instance, which is more than PostgreSQL handles well.
    Budget: (max API pods x pool size) + (max worker pods x pool size) + migrations/admin headroom.
    E.g. 20 API pods x 10 + 10 workers x 5 + 50 = 300. If the app needs more, add PgBouncer/RDS Proxy
    instead of raising this. Static parameter: applied at the next reboot.
  EOT
  type        = number
  default     = 400
}

variable "postgres_backup_retention_days" {
  description = "Automated backup retention. >= 1 enables point-in-time recovery; we require >= 7."
  type        = number
  default     = 14

  validation {
    condition     = var.postgres_backup_retention_days >= 7 && var.postgres_backup_retention_days <= 35
    error_message = "postgres_backup_retention_days must be between 7 and 35."
  }
}

variable "deletion_protection" {
  description = "Deletion protection on RDS and EKS. Only disable deliberately before tearing a stack down."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Redis-compatible queue (ElastiCache Valkey)
# -----------------------------------------------------------------------------

variable "redis_engine_version" {
  description = "Valkey engine version (Redis OSS 7.2 protocol compatible)."
  type        = string
  default     = "8.0"
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.r7g.large"
}

variable "redis_num_cache_clusters" {
  description = "Nodes in the replication group (1 primary + N-1 replicas). >= 2 is required for automatic failover."
  type        = number
  default     = 2

  validation {
    condition     = var.redis_num_cache_clusters >= 2
    error_message = "redis_num_cache_clusters must be >= 2 so Multi-AZ automatic failover works."
  }
}

variable "redis_auth_token_version" {
  description = "Bump (1 -> 2 -> ...) to rotate the Redis AUTH token. The token is write-only: it is never stored in Terraform state."
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch retention for EKS control-plane and RDS logs."
  type        = number
  default     = 30
}
