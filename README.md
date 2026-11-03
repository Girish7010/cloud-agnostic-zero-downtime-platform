
# Cloud-Agnostic Automated Deployment Platform

Starter implementation for the DevOps assignment. This repository is a **scaffold**, not proof of a production deployment.

## Status labels
- `IMPLEMENTED_AND_TESTED`: executed successfully with evidence.
- `IMPLEMENTED_NOT_FULLY_TESTED`: files/configuration exist, but full validation is incomplete.
- `DESIGNED_NOT_IMPLEMENTED`: documented only.
- `BLOCKED_BY_MISSING_DEPENDENCY`: requires the supplied black-box application or credentials.

## Architecture
- Provider layer: Terraform for AWS and local Kubernetes.
- Platform layer: Kubernetes, Helm, Argo CD/Rollouts, Prometheus, KEDA.
- Application layer: immutable API and worker images supplied by the assignment owner.

## Prerequisites
Docker, Git, Terraform, kubectl, Helm, kind or k3d, and (for AWS) AWS CLI credentials.
Do not run `terraform apply` until you have reviewed the plan and estimated cost.

## Local workflow
1. Inspect the supplied API/worker repository and identify immutable image names.
2. Create a local cluster: `kind create cluster --name devops-assignment`
3. Copy `terraform/terraform.tfvars.example` to an appropriate environment file and edit values.
4. Validate Terraform: `terraform -chdir=infra/providers/aws fmt -check -recursive` and `terraform -chdir=infra/providers/aws validate` after init.
5. Configure `deploy/values.example.yaml` with the supplied image repository and digest.
6. Deploy only after PostgreSQL/Redis endpoints and credentials are configured.
7. Run smoke and load tests; save unedited outputs under `evidence/`.

## Important
The application is a black box. Do not invent or rewrite its behavior. The Helm chart uses image placeholders until the actual API and worker image references, ports, environment variables, and startup behavior are confirmed.

Database migrations run on startup and may be incompatible. A safe expand/contract plan is documented in `docs/database-migrations.md`; do not assume an old application can run against a contracted schema.
=======
# cloud-agnostic-zero-downtime-platform
Cloud-agnostic automated deployment platform with Terraform, Kubernetes, GitOps and zero-downtime deployments.

