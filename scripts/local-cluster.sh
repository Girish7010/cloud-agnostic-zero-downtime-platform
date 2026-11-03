#!/usr/bin/env bash
set -euo pipefail
if ! command -v kind >/dev/null 2>&1; then
  echo "kind is not installed. Install kind or use k3d."
  exit 1
fi
kind get clusters | grep -qx devops-assignment || kind create cluster --name devops-assignment
kubectl cluster-info
kubectl get nodes
