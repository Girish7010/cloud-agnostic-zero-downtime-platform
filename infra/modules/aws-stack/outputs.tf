# -----------------------------------------------------------------------------
# Provider-neutral output contract. infra/providers/local exposes the same
# names, so the platform layer and GitOps values never depend on which target
# produced them. Keep both in sync (see infra/README.md).
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Kubernetes cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint."
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Command that writes a kubeconfig entry for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --alias ${module.eks.cluster_name}"
}

output "postgres_host" {
  description = "PostgreSQL hostname (Multi-AZ: the DNS name follows failover)."
  value       = aws_db_instance.this.address
}

output "postgres_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "postgres_secret_ref" {
  description = "Reference to the PostgreSQL credentials in the secret store (Secrets Manager ARN of the RDS-managed secret). Not the secret itself."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "redis_host" {
  description = "Primary endpoint of the Valkey replication group (follows failover). TLS required."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  description = "Redis/Valkey port."
  value       = aws_elasticache_replication_group.this.port
}

output "redis_secret_ref" {
  description = "Reference to the Redis AUTH token in the secret store."
  value       = aws_secretsmanager_secret.redis_auth.arn
}

output "secret_store" {
  description = "Which secret backend the External Secrets Operator ClusterSecretStore must use."
  value       = "aws-secrets-manager"
}

output "region" {
  description = "Region of the stack."
  value       = var.region
}

output "data_residency" {
  description = "Residency class of the stack."
  value       = var.data_residency
}

# --- AWS-specific extras (consumed by infra/platform when target = "aws") ---

output "vpc_id" {
  description = "VPC ID (needed by the AWS Load Balancer Controller)."
  value       = module.vpc.vpc_id
}

output "kms_key_arn" {
  description = "Stack KMS key ARN."
  value       = aws_kms_key.this.arn
}
