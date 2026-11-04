variable "cluster_name" {
  description = "kind cluster name (matches the repo README: kind create cluster --name devops-assignment)."
  type        = string
  default     = "devops-assignment"
}

variable "node_image" {
  description = "kindest/node image, e.g. kindest/node:v1.35.0. null = the default image of the kind version bundled in the provider."
  type        = string
  default     = null
}

variable "worker_count" {
  description = "Worker nodes. 2 lets PodDisruptionBudgets and anti-affinity be exercised during rollouts."
  type        = number
  default     = 2
}

variable "app_namespace" {
  description = "Namespace of the application Helm release."
  type        = string
  default     = "devops-platform"
}

variable "app_release" {
  description = "Helm release name of the application chart (deploy/chart). Redis Service is <release>-redis."
  type        = string
  default     = "devops-platform"
}
