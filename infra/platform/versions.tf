terraform {
  required_version = ">= 1.10.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # No backend block: local state by default (fine for the kind target).
  # For an AWS stack, copy backend.s3.tf.example to backend.tf so platform
  # state is remote, encrypted and locked like the provider layer.
}
