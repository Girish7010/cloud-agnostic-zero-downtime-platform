variable "target" {
  description = "Which provider layer produced the cluster: \"aws\" (EKS) or \"local\" (kind)."
  type        = string

  validation {
    condition     = contains(["aws", "local"], var.target)
    error_message = "target must be \"aws\" or \"local\"."
  }
}

variable "kubeconfig_path" {
  description = "Path to the kubeconfig. AWS: run the provider layer's kubeconfig_command output first. Local: providers/local output kubeconfig_path."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use (AWS: the cluster name, given --alias; kind: kind-devops-assignment)."
  type        = string
}

# ---- AWS-only inputs (from the provider layer outputs) ----

variable "cluster_name" {
  description = "Cluster name (provider layer output cluster_name). Required for target = aws."
  type        = string
  default     = null

  validation {
    condition     = var.target != "aws" || var.cluster_name != null
    error_message = "cluster_name is required when target = \"aws\"."
  }
}

variable "region" {
  description = "AWS region (provider layer output region). Required for target = aws."
  type        = string
  default     = null

  validation {
    condition     = var.target != "aws" || var.region != null
    error_message = "region is required when target = \"aws\"."
  }
}

variable "vpc_id" {
  description = "VPC ID (provider layer output vpc_id). Required for target = aws."
  type        = string
  default     = null

  validation {
    condition     = var.target != "aws" || var.vpc_id != null
    error_message = "vpc_id is required when target = \"aws\"."
  }
}

variable "cluster_autoscaler_image_tag" {
  description = "cluster-autoscaler image tag. Its minor version MUST match the EKS Kubernetes minor (modules/aws-stack var.kubernetes_version)."
  type        = string
  default     = "v1.35.0"
}
