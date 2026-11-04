# -----------------------------------------------------------------------------
# Redis-compatible job queue: ElastiCache for Valkey (Redis OSS protocol
# compatible, cheaper than the Redis OSS engine on ElastiCache).
#   - 1 primary + replicas in different AZs, automatic failover
#   - TLS in transit + AUTH token, encrypted at rest with the stack key
#   - maxmemory-policy noeviction: this is a QUEUE, silently evicting jobs
#     under memory pressure is worse than rejecting new writes
# NOTE: TLS means the app must connect with rediss:// (black-box app: verify).
#
# AUTH token without secrets in state: the token is generated as an
# *ephemeral* value (never persisted) and passed only to write-only
# arguments (auth_token_wo, secret_string_wo). Terraform >= 1.11 required.
# Rotate by bumping var.redis_auth_token_version; ROTATE strategy keeps the
# old token valid until the app has picked up the new one.
# -----------------------------------------------------------------------------

resource "aws_security_group" "redis" {
  name        = "${local.name}-redis"
  description = "Valkey/Redis: reachable only from EKS nodes/pods of this stack"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_nodes" {
  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  description                  = "Valkey from EKS nodes"
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis"
  subnet_ids = module.vpc.database_subnets
  tags       = local.tags
}

resource "aws_elasticache_parameter_group" "redis" {
  name   = "${local.name}-valkey8"
  family = "valkey8"
  tags   = local.tags

  parameter {
    name  = "maxmemory-policy"
    value = "noeviction"
  }
}

ephemeral "random_password" "redis_auth" {
  length  = 64
  special = false # ElastiCache AUTH forbids some specials (@ " /); alnum x64 is plenty
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name                    = "${local.name}/redis-auth"
  description             = "AUTH token for ${local.name} ElastiCache (synced to Kubernetes by External Secrets Operator)"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 7
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id                = aws_secretsmanager_secret.redis_auth.id
  secret_string_wo         = ephemeral.random_password.redis_auth.result
  secret_string_wo_version = var.redis_auth_token_version
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${local.name}-redis"
  description          = "${local.name} job queue"

  engine               = "valkey"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_clusters   = var.redis_num_cache_clusters
  parameter_group_name = aws_elasticache_parameter_group.redis.name
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  automatic_failover_enabled = true
  multi_az_enabled           = true

  at_rest_encryption_enabled = true
  kms_key_id                 = aws_kms_key.this.arn
  transit_encryption_enabled = true
  auth_token_wo              = ephemeral.random_password.redis_auth.result
  auth_token_wo_version      = var.redis_auth_token_version
  auth_token_update_strategy = "ROTATE"

  # Daily snapshots, kept in-region (residency), a few days is enough for a
  # queue whose source of truth for business data is PostgreSQL.
  snapshot_retention_limit = 3
  snapshot_window          = "01:00-02:00"
  maintenance_window       = "sun:04:30-sun:05:30"

  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = local.tags
}
