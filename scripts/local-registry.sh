#!/usr/bin/env bash
# Local OCI registry for kind so workloads can be deployed by immutable digest.
# Usage: scripts/local-registry.sh [local-image:tag]   -> pushes and prints digest
set -euo pipefail
NODE="${NODE:-devops-assignment-control-plane}"
if ! docker inspect kind-registry >/dev/null 2>&1; then
  docker run -d --restart=always -p 127.0.0.1:5001:5000 --network kind --name kind-registry --memory 128m registry:2
fi
docker exec "$NODE" sh -c 'mkdir -p /etc/containerd/certs.d/localhost:5001 && printf "[host.\"http://kind-registry:5000\"]\n" > /etc/containerd/certs.d/localhost:5001/hosts.toml'
if [ $# -ge 1 ]; then
  name="${1%%:*}"; tag="${1##*:}"
  docker tag "$1" "localhost:5001/$name:$tag"
  docker push -q "localhost:5001/$name:$tag" >/dev/null
  docker buildx imagetools inspect "localhost:5001/$name:$tag" --format '{{json .Manifest.Digest}}' | tr -d '"'
fi
