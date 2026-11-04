output "state_bucket_name" {
  description = "Use as `bucket` in backend.hcl."
  value       = aws_s3_bucket.state.bucket
}

output "state_kms_key_arn" {
  description = "Use as `kms_key_id` in backend.hcl."
  value       = aws_kms_key.state.arn
}

output "state_region" {
  description = "Use as `region` in backend.hcl."
  value       = var.region
}

output "github_plan_role_arn" {
  description = "Role for plan/drift jobs (aws-actions/configure-aws-credentials role-to-assume)."
  value       = aws_iam_role.plan.arn
}

output "github_apply_role_arn" {
  description = "Role for apply jobs running in the production environment."
  value       = aws_iam_role.apply.arn
}
