# Same output contract as modules/aws-stack (see infra/README.md). Data stores
# are in-cluster Services created by the app chart (Redis) and
# database/postgres-test.yaml (PostgreSQL), so hosts are cluster DNS names.

output "cluster_name" {
  value = kind_cluster.this.name
}

output "cluster_endpoint" {
  value = kind_cluster.this.endpoint
}

output "kubeconfig_command" {
  value = "kind export kubeconfig --name ${kind_cluster.this.name}"
}

output "kubeconfig_path" {
  description = "Local only: kubeconfig written by the provider (feed to infra/platform var.kubeconfig_path)."
  value       = kind_cluster.this.kubeconfig_path
}

output "kube_context" {
  description = "Local only: kube context name."
  value       = kind_cluster.this.context_name
}

output "postgres_host" {
  value = "migration-postgres.${var.app_namespace}.svc"
}

output "postgres_port" {
  value = 5432
}

output "postgres_secret_ref" {
  description = "Kubernetes Secret holding the disposable test DB password (namespace/name), see database/postgres-test.yaml."
  value       = "${var.app_namespace}/migration-db-secret"
}

output "redis_host" {
  value = "${var.app_release}-redis.${var.app_namespace}.svc"
}

output "redis_port" {
  value = 6379
}

output "redis_secret_ref" {
  description = "Local Redis runs without AUTH (disposable)."
  value       = null
}

output "secret_store" {
  description = "Plain Kubernetes Secrets locally (ESO kubernetes provider can be used to mirror the AWS flow)."
  value       = "kubernetes"
}

output "region" {
  value = "local"
}

output "data_residency" {
  description = "A laptop/CI runner is not a residency control; local data must be synthetic."
  value       = "local"
}
