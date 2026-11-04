# -----------------------------------------------------------------------------
# Platform layer: cluster add-ons shared by every app and tenant.
# Terraform installs the controllers; applications (API, worker, Redis on
# local) are deployed by Argo CD / Helm from Git, NOT by Terraform.
#
# Chart versions are pinned exactly (looked up from each repo's index.yaml on
# 2026-11-04) so a plan never silently upgrades a controller. Bump them in one
# reviewed change.
# -----------------------------------------------------------------------------

locals {
  is_aws   = var.target == "aws"
  is_local = var.target == "local"

  charts = {
    metrics_server        = { repo = "https://kubernetes-sigs.github.io/metrics-server/", chart = "metrics-server", version = "3.14.0" }          # app 0.9.0
    keda                  = { repo = "https://kedacore.github.io/charts", chart = "keda", version = "2.21.0" }                                    # app 2.21.0
    external_secrets      = { repo = "https://charts.external-secrets.io", chart = "external-secrets", version = "2.14.0" }                       # app v2.14.0
    argo_cd               = { repo = "https://argoproj.github.io/argo-helm", chart = "argo-cd", version = "10.11.7" }                             # app v3.5.7
    argo_rollouts         = { repo = "https://argoproj.github.io/argo-helm", chart = "argo-rollouts", version = "2.43.8" }                        # app v1.10.1
    kube_prometheus_stack = { repo = "https://prometheus-community.github.io/helm-charts", chart = "kube-prometheus-stack", version = "92.17.1" } # operator v0.94.2
    aws_lb_controller     = { repo = "https://aws.github.io/eks-charts", chart = "aws-load-balancer-controller", version = "3.6.2" }              # app v3.6.2
    cluster_autoscaler    = { repo = "https://kubernetes.github.io/autoscaler", chart = "cluster-autoscaler", version = "9.60.0" }
  }

  # Namespaces we own, with Pod Security Admission labels: enforce "baseline"
  # (blocks privileged/host access), warn on "restricted" so gaps show up in
  # kubectl output without breaking installs. monitoring must be privileged
  # because node-exporter uses hostNetwork/hostPID/hostPath.
  namespaces = {
    keda             = "baseline"
    external-secrets = "baseline"
    argocd           = "baseline"
    argo-rollouts    = "baseline"
    monitoring       = "privileged"
  }
}

resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by"       = "terraform"
      "pod-security.kubernetes.io/enforce" = each.value
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

# --- Resource metrics for HPA (CPU/memory) ---------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = local.charts.metrics_server.repo
  chart      = local.charts.metrics_server.chart
  version    = local.charts.metrics_server.version

  values = [yamlencode({
    # !!! LOCAL ONLY !!! kind kubelets serve self-signed certificates, so
    # metrics-server cannot verify them. This flag disables kubelet TLS
    # verification and must NEVER be set on a real cluster (EKS kubelet certs
    # are verifiable, so target = "aws" leaves args empty).
    args = local.is_local ? ["--kubelet-insecure-tls"] : []
  })]
}

# --- Event-driven autoscaling (worker scales on Redis queue length) --------
resource "helm_release" "keda" {
  name       = "keda"
  namespace  = kubernetes_namespace_v1.this["keda"].metadata[0].name
  repository = local.charts.keda.repo
  chart      = local.charts.keda.chart
  version    = local.charts.keda.version
}

# --- Secrets: cloud secret store -> Kubernetes Secret ----------------------
# On AWS the service account below is bound to a read-only IAM role by an EKS
# Pod Identity association created in modules/aws-stack (namespace and name
# must stay "external-secrets"). The ClusterSecretStore / ExternalSecret
# objects are app config and are delivered by GitOps.
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  namespace  = kubernetes_namespace_v1.this["external-secrets"].metadata[0].name
  repository = local.charts.external_secrets.repo
  chart      = local.charts.external_secrets.chart
  version    = local.charts.external_secrets.version

  values = [yamlencode({
    installCRDs    = true
    serviceAccount = { name = "external-secrets" }
  })]
}

# --- GitOps ------------------------------------------------------------------
resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  namespace  = kubernetes_namespace_v1.this["argocd"].metadata[0].name
  repository = local.charts.argo_cd.repo
  chart      = local.charts.argo_cd.chart
  version    = local.charts.argo_cd.version

  values = [yamlencode({
    dex = { enabled = false } # no SSO configured yet; admin via initial secret
    # Two repo-server/server replicas on AWS so a node drain does not stop sync.
    server     = { replicas = local.is_aws ? 2 : 1 }
    repoServer = { replicas = local.is_aws ? 2 : 1 }
  })]
}

# --- Progressive delivery (canary / blue-green for the API) ----------------
resource "helm_release" "argo_rollouts" {
  name       = "argo-rollouts"
  namespace  = kubernetes_namespace_v1.this["argo-rollouts"].metadata[0].name
  repository = local.charts.argo_rollouts.repo
  chart      = local.charts.argo_rollouts.chart
  version    = local.charts.argo_rollouts.version

  values = [yamlencode({
    controller = { replicas = local.is_aws ? 2 : 1 } # leader election handles HA
  })]
}

# --- Monitoring (Prometheus feeds Argo Rollouts analysis and KEDA) ---------
# Grafana admin password: generated here, so it IS in this root's state
# (remote, KMS-encrypted on AWS). Grafana is ClusterIP only (not exposed).
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.this["monitoring"].metadata[0].name
  repository = local.charts.kube_prometheus_stack.repo
  chart      = local.charts.kube_prometheus_stack.chart
  version    = local.charts.kube_prometheus_stack.version
  timeout    = 900 # CRDs + many components

  values = [yamlencode({
    grafana = { adminPassword = random_password.grafana_admin.result }
    prometheus = {
      prometheusSpec = {
        retention = "7d"
        # Pick up ServiceMonitors/PodMonitors from any namespace (the app chart),
        # not only those labelled for this Helm release.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
      }
    }
    # Control-plane components are not scrapeable on EKS (managed) and bind to
    # localhost on kind; disable to avoid permanently-down targets/alerts.
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false }
  })]
}

# --- AWS-only controllers (pod identity roles come from modules/aws-stack) --

# Turns Kubernetes Ingress/Service type LoadBalancer into ALB/NLB.
resource "helm_release" "aws_load_balancer_controller" {
  count = local.is_aws ? 1 : 0

  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = local.charts.aws_lb_controller.repo
  chart      = local.charts.aws_lb_controller.chart
  version    = local.charts.aws_lb_controller.version

  values = [yamlencode({
    clusterName    = var.cluster_name
    region         = var.region
    vpcId          = var.vpc_id
    replicaCount   = 2
    serviceAccount = { name = "aws-load-balancer-controller" }
  })]
}

# Scales the EKS managed node groups between their min and max size.
resource "helm_release" "cluster_autoscaler" {
  count = local.is_aws ? 1 : 0

  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = local.charts.cluster_autoscaler.repo
  chart      = local.charts.cluster_autoscaler.chart
  version    = local.charts.cluster_autoscaler.version

  values = [yamlencode({
    cloudProvider = "aws"
    awsRegion     = var.region
    autoDiscovery = { clusterName = var.cluster_name }
    image         = { tag = var.cluster_autoscaler_image_tag }
    rbac          = { serviceAccount = { name = "cluster-autoscaler" } }
    extraArgs = {
      "balance-similar-node-groups" = true
      "expander"                    = "least-waste"
      # Do not remove nodes running pods with local storage (e.g. Prometheus
      # emptyDir) just to save cost; Rollouts need stable capacity.
      "skip-nodes-with-local-storage" = true
    }
  })]
}
