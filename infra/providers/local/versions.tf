terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # Community provider (not HashiCorp-maintained) wrapping the kind Go library.
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13"
    }
  }

  # Local state on purpose: the kind cluster is disposable and per-laptop/CI
  # runner. There is nothing to share or lock.
}
