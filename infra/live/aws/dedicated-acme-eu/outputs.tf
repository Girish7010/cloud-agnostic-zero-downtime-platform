# Re-export the provider-neutral contract of modules/aws-stack unchanged.
# CI reads these with `terraform output -json` to feed infra/platform and
# GitOps values. Same names as infra/providers/local/outputs.tf.

output "cluster_name" {
  value = module.stack.cluster_name
}

output "cluster_endpoint" {
  value = module.stack.cluster_endpoint
}

output "kubeconfig_command" {
  value = module.stack.kubeconfig_command
}

output "postgres_host" {
  value = module.stack.postgres_host
}

output "postgres_port" {
  value = module.stack.postgres_port
}

output "postgres_secret_ref" {
  value = module.stack.postgres_secret_ref
}

output "redis_host" {
  value = module.stack.redis_host
}

output "redis_port" {
  value = module.stack.redis_port
}

output "redis_secret_ref" {
  value = module.stack.redis_secret_ref
}

output "secret_store" {
  value = module.stack.secret_store
}

output "region" {
  value = module.stack.region
}

output "data_residency" {
  value = module.stack.data_residency
}

output "vpc_id" {
  value = module.stack.vpc_id
}
