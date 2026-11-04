output "installed_charts" {
  description = "Pinned chart versions installed on this target."
  value = merge(
    { for k, c in local.charts : k => "${c.chart}@${c.version}" if !contains(["aws_lb_controller", "cluster_autoscaler"], k) },
    local.is_aws ? {
      aws_lb_controller  = "${local.charts.aws_lb_controller.chart}@${local.charts.aws_lb_controller.version}"
      cluster_autoscaler = "${local.charts.cluster_autoscaler.chart}@${local.charts.cluster_autoscaler.version}"
    } : {}
  )
}

output "grafana_admin_password" {
  description = "Grafana admin password (kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80)."
  value       = random_password.grafana_admin.result
  sensitive   = true
}
