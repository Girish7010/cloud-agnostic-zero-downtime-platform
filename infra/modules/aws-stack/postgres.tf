# -----------------------------------------------------------------------------
# PostgreSQL 16 on RDS.
# Credentials: manage_master_user_password = true makes RDS generate the master
# password and keep it in Secrets Manager (encrypted with the stack key, rotated
# by RDS). Terraform only ever sees the secret ARN, never the password, so it is
# not in code, tfvars or state. ESO syncs it into the cluster.
# Next step: a least-privilege application role created by the migration job,
# so the app does not connect as the master user.
#
# Residency: automated backups and snapshots stay in this region. No
# aws_db_instance_automated_backups_replication (cross-region copy) is
# configured, and none may be added for data_residency = "eu" outside eu-*.
# -----------------------------------------------------------------------------

resource "aws_security_group" "postgres" {
  name        = "${local.name}-postgres"
  description = "PostgreSQL: reachable only from EKS nodes/pods of this stack"
  vpc_id      = module.vpc.vpc_id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes (pods use the node SG with VPC CNI defaults)"
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${local.name}-postgres16"
  family = "postgres16"
  tags   = local.tags

  # See var.postgres_max_connections for the sizing rationale.
  parameter {
    name         = "max_connections"
    value        = tostring(var.postgres_max_connections)
    apply_method = "pending-reboot"
  }

  # Reject non-TLS client connections.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log statements slower than 500 ms (useful during expand/contract migrations).
  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }
}

# RDS would create this log group itself with infinite retention and no CMK;
# creating it first lets us set retention and encryption.
resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/aws/rds/instance/${local.name}-postgres/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.this.arn
  tags              = local.tags
}

resource "aws_db_instance" "this" {
  identifier     = "${local.name}-postgres"
  engine         = "postgres"
  engine_version = var.postgres_engine_version
  instance_class = var.postgres_instance_class

  db_name                       = "app"
  username                      = "app_admin"
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.this.arn

  allocated_storage     = var.postgres_allocated_storage_gb
  max_allocated_storage = var.postgres_allocated_storage_gb * 5
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.this.arn

  multi_az               = var.postgres_multi_az
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  publicly_accessible    = false
  parameter_group_name   = aws_db_parameter_group.postgres.name
  ca_cert_identifier     = "rds-ca-rsa2048-g1"

  # Backups: retention >= 7 days; with retention > 0 RDS also keeps
  # transaction logs, which is what enables point-in-time recovery.
  backup_retention_period   = var.postgres_backup_retention_days
  backup_window             = "02:00-03:00"
  maintenance_window        = "sun:03:30-sun:04:30"
  copy_tags_to_snapshot     = true
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-postgres-final"

  # Minor upgrades in the maintenance window; never apply changes mid-day.
  auto_minor_version_upgrade = true
  apply_immediately          = false

  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.this.arn
  enabled_cloudwatch_logs_exports = ["postgresql"]

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.postgres]
}
