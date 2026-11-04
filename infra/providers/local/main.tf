# -----------------------------------------------------------------------------
# Local provider layer: a kind cluster.
#
# Choice: the tehcyx/kind provider creates the cluster so the local target has
# the same "terraform apply -> cluster + output contract" shape as AWS. The
# alternative (static outputs over a cluster made by `kind create cluster`)
# was rejected because the endpoint would have to be typed in by hand. If a
# cluster with this name already exists (e.g. created per the repo README),
# delete it first (`kind delete cluster --name devops-assignment`) or change
# var.cluster_name; Terraform will not adopt it.
#
# What is NOT emulated locally: managed PostgreSQL/Redis (they run as
# disposable in-cluster pods, no HA, no backups), cloud IAM / Pod Identity,
# KMS, cloud load balancers, VPC networking, node autoscaling.
#
# Note: the kind_cluster resource keeps the cluster's client key in the local
# state file. Acceptable for a throwaway cluster; never reuse this pattern for
# a shared cluster.
# -----------------------------------------------------------------------------

resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true
  # Written next to this root and gitignored (infra/.gitignore).
  kubeconfig_path = abspath("${path.module}/kubeconfig")

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
