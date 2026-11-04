# Provider-agnostic: both targets are reached through a kubeconfig, so the
# same code installs the platform on EKS and on kind.

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}
