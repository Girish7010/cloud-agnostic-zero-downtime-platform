# Cloud-Agnostic, Automated, Zero-Downtime Deployment Platform
<img width="1216" height="826" alt="image" src="https://github.com/user-attachments/assets/2a90775b-2959-44d1-9533-8a8e79329289" />


## Overview and objectives
This repository is my solution to the *Senior DevOps Assignment: Cloud-Agnostic, Automated, Zero-Downtime Deployment Platform*. The goal is a platform that provisions infrastructure on any cloud, deploys a stateless API and a Redis-queue worker (backed by PostgreSQL and Redis) through a multi-stage pipeline with zero downtime, scales to 15x peak load, and supports both a shared stack and dedicated per-tenant stacks with EU data residency.

What is in it:
- Terraform provider layer
- Kubernetes platform layer
- one Helm template for shared and dedicated tenants
- a build-once/sign/promote-by-digest pipeline
- metric-gated rollouts with automatic rollback
- queue-depth worker autoscaling
- EU residency guards

> **Read this first: what is real.**
> - **Proven locally on kind:** deploy under load, automatic rollback, worker drain, backup/restore, tenancy, fleet halt and autoscaling. Evidence is in [`evidence/submission-2026-11-04/`](evidence/submission-2026-11-04/README.md).
> - **Validated, not applied:** the AWS IaC. No cloud resources exist, and the 2,250 rps test was **not** run.
> - **Not the black box:** the app in `app/` is a **reference test harness**, not the assignment's black-box application, which wasn't supplied. Details: [`limitations.md`](evidence/submission-2026-11-04/limitations.md).

## Architecture overview
Three layers that talk only through a fixed output contract (cluster endpoint, database/Redis hosts, secret references, region, residency):

| Layer | What | Where |
|---|---|---|
| Provider | Network, Kubernetes, PostgreSQL, Redis/Valkey, KMS, secrets, IAM/OIDC, remote state | `infra/` (Terraform: AWS module + local kind target) |
| Platform | metrics-server, KEDA, External Secrets, Argo CD/Rollouts, Prometheus | `infra/platform` |
| Application | One Helm chart for the API and worker, one values file per tenant, rollout rings | `deploy/chart`, `gitops/` |

Request flow: client → Service/load balancer → API pods (`/healthz`, `/readyz`, `/metrics`) → Redis stream → worker pods → PostgreSQL. The API scales on CPU (HPA) and workers scale on queue lag (KEDA). Every release goes out by immutable image digest through a gated rollout that rolls back automatically on probe or metric failure. Full detail, diagrams, decisions and risks: [`docs/pdf/architecture.pdf`](docs/pdf/architecture.pdf) (5 pages; source [`docs/architecture.md`](docs/architecture.md)).

## Technology stack
| Area | Tools |
|---|---|
| Application (reference harness) | Python 3.13, FastAPI/uvicorn, Redis Streams, Prometheus client |
| Containers | Docker (one image for API and worker), GHCR registry, images pinned by digest |
| Orchestration | Kubernetes (kind locally; EKS designed), Helm 4, HPA, KEDA 2.21 |
| Infrastructure as code | Terraform ≥ 1.11 (AWS provider, S3 native state locking, `terraform test`) |
| CI/CD | GitHub Actions, Trivy 0.70.0, syft (CycloneDX SBOM), Cosign keyless signing, GitHub Environments with required reviewers |
| GitOps / progressive delivery (config, not deployed) | Argo CD ApplicationSet, Argo Rollouts |
| Data | PostgreSQL 16, Redis 7 (Valkey on AWS) |
| Testing | pytest + fakeredis, k6 (in-cluster), shellcheck, actionlint |

## Deliverables
| Deliverable | Location |
|---|---|
| Architecture document (≤ 5 pages: diagram, 8 decisions with rejected alternatives, top 5 risks, capacity, failure modes) | [`docs/pdf/architecture.pdf`](docs/pdf/architecture.pdf) · source [`docs/architecture.md`](docs/architecture.md) |
| Evidence (deploy under load, automatic rollback, 15x-ratio load, restore, drain, tenancy) | [`evidence/submission-2026-11-04/README.md`](evidence/submission-2026-11-04/README.md) |
| Change request: second cloud, US-West primary / US-East failover (1 page) | [`docs/pdf/change-request-us.pdf`](docs/pdf/change-request-us.pdf) · source [`docs/change-request-us.md`](docs/change-request-us.md) |
| Cost estimate (steady/peak) · 90-day roadmap | [`docs/cost-estimate.md`](docs/cost-estimate.md) · [`docs/90-day-roadmap.md`](docs/90-day-roadmap.md) |
| Operations (SLOs, alerts, backups) · runbooks | [`docs/operations.md`](docs/operations.md) · [`docs/runbooks/`](docs/runbooks/) |
| Review preparation | [`docs/review-prep.md`](docs/review-prep.md) |
| Submission guide · final report | [`SUBMISSION_GUIDE.md`](SUBMISSION_GUIDE.md) · [`FINAL_SUBMISSION_REPORT.md`](evidence/submission-2026-11-04/FINAL_SUBMISSION_REPORT.md) |

## Repository layout
```
app/                    reference test harness (API + worker) — NOT the black-box app
tests/unit/             pytest (Redis mocked with fakeredis)
tests/load/             k6 scripts (platform.js = business path, in-cluster)
deploy/chart/           Helm chart "platform-app": API, worker, PDBs, HPA, KEDA ScaledObject,
                        NetworkPolicies, residency affinity, local Redis (AOF)
deploy/environments/    local (digest from local registry), dev / staging / production values
gitops/                 tenants/<id>/values.yaml (one file = one tenant), fleet.yaml (rings),
                        argocd/ ApplicationSet, rollouts/ canary + analysis, observability/ alert rules
infra/                  Terraform: bootstrap (state + OIDC), modules/aws-stack, live/aws/{shared-eu,
                        dedicated-acme-eu}, providers/{aws,local}, platform (add-ons) — see infra/README.md
.github/workflows/      ci.yml (build once → scan → SBOM → sign → promote), promote.yml, drift-detection.yml
scripts/                gated rollout, fleet rollout, onboarding, load/drain/restore/isolation tests
database/               expand/backfill/contract SQL demo + local PostgreSQL manifest
evidence/               raw logs and reports (failed attempts included)
```

## Status matrix
Labels:
- **Tested-local:** ran on kind with evidence.
- **Implemented:** code/config exists and validates, but was not executed against real infrastructure.
- **Design:** documented only.
- **Not done**

| Requirement | Status | Evidence / location |
|---|---|---|
| Provider / platform / app layer separation | Implemented | `infra/`, `deploy/chart`, `docs/architecture.md` §1 |
| Two targets: local kind + AWS | kind: Tested-local · AWS: Implemented (validate + `terraform test` 4/4, **not applied**) | `terraform-validation.txt` |
| Empty account → platform, no console | Implemented (bootstrap → live → platform → GitOps), not executed | `infra/README.md` |
| Remote state + locking, drift detection | Implemented (S3 native lock, nightly plan via OIDC), not executed | `infra/bootstrap`, `drift-detection.yml` |
| Secrets manager | Implemented (RDS-managed secret, ESO), not executed | `infra/modules/aws-stack` |
| Non-portable components listed | Design | `docs/architecture.md` §1, `infra/README.md` |
| Unit tests | Tested-local (14/14) | `test-results.txt` |
| Build once, scan, SBOM, sign, promote same digest | **Tested in CI**: final [run 41810479665](https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665) (#5, commit `9d747ff`) green; it promoted one digest to `dev`, `staging` and `production` ([ci-run.txt](evidence/submission-2026-11-04/ci-run.txt)) | `.github/workflows/ci.yml`, `promote.yml` |
| Deploy by immutable digest | Tested-local (local OCI registry) | `deploy/environments/local.yaml` |
| Approval gates | **Tested in CI**: `staging` and `production` require a reviewer; both were approved manually in run 41810479665 | `ci.yml` |
| Metric-based deployment gates + automatic rollback | Tested-local (`gated-rollout.sh`); cloud canary = Design | `rollback-bad-release-*`, `gitops/rollouts/` |
| Deploy under load with no errors | Tested-local: **36,001 req @150 rps, 0 failed** | `deploy-under-load/` |
| API probes, graceful shutdown, PDB | Tested-local | chart, `deploy-under-load/` |
| Worker draining (60 s jobs) | Tested-local: interrupted 45 s job completed + ACKed, pending 0 | `worker-drain/` |
| Safe DB migrations (expand/contract) | SQL demo Tested-local; app startup integration **Not done** | `docs/database-migrations.md` |
| GitOps pull | Design (ApplicationSet); local demo uses pipeline push | `gitops/argocd/` |
| Rollout order rings + halt on failure | Tested-local (3 rings; bad release halted at ring 0) | `fleet-rollout-good/`, `fleet-rollout-halt/` |
| HPA autoscaling (API) | Tested-local (2→5 at 150 rps) | `deploy-under-load/`, `load-15x-ratio/` |
| Queue-depth worker scaling (KEDA) | Tested-local | `load-15x-ratio/`, `keda-install/` |
| 15x scale in < 5 min and back, no dropped jobs | Tested-local as **15x ratio (10→150 rps)** only; **2,250 rps Not done** | `load-15x-ratio/`, `docs/architecture.md` §3 |
| Capacity maths + DB limits | Design | `docs/architecture.md` §3 |
| Shared + dedicated stacks from one template | Tested-local (k8s layer); cloud dedicated stack Implemented | `gitops/tenants/`, `infra/live/aws/` |
| New tenant < 30 min from one reviewed change | Tested-local: 16 s (k8s layer); cloud stack estimated 20–25 min | `tenant-onboarding/` |
| Tenant isolation | Tested-local (9/9 incl. positive controls) | `isolation-residency/` |
| EU data stays in EU | Tested-local (policy gate + scheduler guard) + Terraform test (mocked) | `isolation-residency/`, `infra/modules/aws-stack/tests/` |
| SLOs, alerts, per-tenant visibility | Implemented as config (not deployed); tenant labels Tested-local | `docs/operations.md`, `gitops/observability/` |
| Runbooks | Design | `docs/runbooks/` |
| Backup + restore test | Tested-local (checksum-identical restore into a new DB) | `backup-restore/` |
| Cost estimate, 90-day roadmap | Design (list-price estimate) | `docs/cost-estimate.md`, `docs/90-day-roadmap.md` |
| Second-cloud US-West/US-East change request | Design | `docs/change-request-us.md` |
| Black-box application deployed | **Not done**: not supplied; reference harness used | `docs/architecture.md` scope note |

## Prerequisites
Docker, kind ≥ 0.24, kubectl, Helm 4, Terraform ≥ 1.11, k6 (optional; the tests use the `grafana/k6` image in-cluster), jq, Python 3.13+. AWS CLI only for a future cloud apply.

## Local setup (kind)
```bash
# 1. Cluster + local OCI registry (images deployed by digest)
scripts/local-cluster.sh
kubectl create namespace devops-platform
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
#    kind only: metrics-server needs --kubelet-insecure-tls (never in cloud)
scripts/local-registry.sh

# 2. Build the image once, push, note the digest
docker build -t cloud-platform-reference:v6 .
scripts/local-registry.sh cloud-platform-reference:v6        # prints sha256:...
#    put that digest into deploy/environments/local.yaml

# 3. Optional: KEDA for queue-depth scaling (else set worker.keda.enabled=false)
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --version 2.21.0 -n keda --create-namespace --wait

# 4. Deploy the shared stack
helm upgrade --install devops-platform ./deploy/chart -n devops-platform \
  -f deploy/environments/local.yaml -f gitops/tenants/shared/values.yaml --wait

# 5. Unit tests and static checks
python -m venv .venv && .venv/bin/pip install -r requirements-dev.txt && .venv/bin/python -m pytest
helm lint deploy/chart
```

## Docker: build and run
One image serves both the API and the worker. It needs Redis. The commands below were run against the CI-built image on 2026-11-04 ([`docker-smoke.txt`](evidence/submission-2026-11-04/docker-smoke.txt)).
```bash
docker build -t cloud-platform-reference:local .
docker network create zd-demo
docker run -d --name zd-redis --network zd-demo redis:7-alpine
docker run -d --name zd-api --network zd-demo -p 8080:8080 -e REDIS_URL=redis://zd-redis:6379/0 cloud-platform-reference:local
docker run -d --name zd-worker --network zd-demo -e REDIS_URL=redis://zd-redis:6379/0 cloud-platform-reference:local python -m app.worker.main
curl localhost:8080/healthz; curl localhost:8080/readyz
curl -X POST localhost:8080/jobs -H 'content-type: application/json' -d '{"job_id":"demo-1","duration_seconds":1}'
docker rm -f zd-api zd-worker zd-redis && docker network rm zd-demo    # clean up
```
The signed CI image can be used instead of a local build: `ghcr.io/girish7010/cloud-platform-reference@sha256:5bd2b6b467805b03c33440c56a84252c470701bc768f0e416782dbffe8ddb0e3`.

## Kubernetes deployment
Step 4 of the local setup installs the shared stack. Production-style releases go through `scripts/gated-rollout.sh`, which runs `helm upgrade --wait --rollback-on-failure` and then four metric-analysis steps, and runs `helm rollback` automatically if a step fails. Every tenant is a values file in `gitops/tenants/`; `scripts/fleet-rollout.sh` rolls the rings out in order and halts on the first failure.

## Operating it
| Task | Command | 
|---|---|
| Gated rollout (auto-rollback on probe or metric failure) | `scripts/gated-rollout.sh -f deploy/environments/local.yaml --set api.image.digest=sha256:...` |
| Deploy under load (evidence) | `scripts/test-deploy-under-load.sh <name> PROFILE=constant RATE=150 DURATION=240s -- <rollout args>` |
| Onboard tenant | add `gitops/tenants/<id>/values.yaml`, then `scripts/onboard-tenant.sh <id>` |
| Fleet rollout by rings (halts on failure) | `scripts/fleet-rollout.sh --set api.image.digest=sha256:...` |
| Manual rollback | `helm rollback devops-platform <rev> -n devops-platform --wait` |
| Worker drain test | `scripts/test-worker-drain.sh` |
| Backup + restore drill | `scripts/backup-restore-postgres.sh` (restores into a new DB; never overwrites) |
| Isolation/residency test | `scripts/test-isolation-residency.sh` |
| 15x-ratio autoscaling test | `scripts/test-15x-ratio.sh` |
| Replay a recording | `scriptreplay --timing=evidence/submission-2026-11-04/recordings/<x>.timing evidence/submission-2026-11-04/recordings/<x>.typescript` |

## Terraform usage (validated, not applied)
No cloud resources exist, and nothing should be applied without approving the spend first ([`docs/cost-estimate.md`](docs/cost-estimate.md)). Safe local checks, with no credentials and no state:
```bash
terraform fmt -check -recursive infra
for d in infra/bootstrap/aws-state infra/modules/aws-stack infra/live/aws/* infra/providers/* infra/platform; do
  terraform -chdir=$d init -backend=false -input=false && terraform -chdir=$d validate; done
terraform -chdir=infra/modules/aws-stack test     # mocked AWS provider, EU-residency tests
```
Order for a real account, documented in [`infra/README.md`](infra/README.md): `bootstrap/aws-state` (state bucket and GitHub OIDC roles) → `live/aws/shared-eu` → `platform` → Argo CD. Review the `terraform plan` before any `apply`.

## CI/CD pipeline
[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` ([Actions](https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/workflows/ci.yml)):
1. **Verify:** unit tests, shellcheck, Helm lint and render of every environment and tenant, Terraform fmt and validate.
2. **Build once:** one `docker build`, pushed to GHCR. Its digest is the release identity from here on.
3. **Scan:** Trivy 0.70.0 (container pinned by digest) fails on any fixable CRITICAL/HIGH vulnerability.
4. **SBOM and sign:** CycloneDX SBOM (syft); keyless Cosign signature and SBOM attestation with the GitHub OIDC token, so there is no signing key to leak.
5. **Promote** ([`promote.yml`](.github/workflows/promote.yml)): for dev, then staging, then production, verify the signature and attestation against this repository's workflow identity, then point the environment tag at the **same digest**. Nothing is rebuilt. Staging and production need a manual approval (GitHub Environment required reviewers).

Pull requests run only the checks: they don't push, sign or promote. [`drift-detection.yml`](.github/workflows/drift-detection.yml) is a nightly `terraform plan` through OIDC; it is skipped until the AWS state bucket and roles exist. Final green run: [41810479665](https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665). Record: [`ci-run.txt`](evidence/submission-2026-11-04/ci-run.txt).

## Security and monitoring
- No secrets in Git or Terraform state. The one exception, the documented local demo, is a Kubernetes Secret created out of band and never committed.
- CI uses OIDC and `GITHUB_TOKEN` only. All actions are pinned to commit SHAs.
- Containers run as UID 1000 with a read-only root filesystem, all capabilities dropped and seccomp `RuntimeDefault`.
- Images are deployed by digest and every promotion re-verifies the Cosign signature and SBOM attestation.
- EU residency is enforced in three places: Terraform validation, the onboarding policy gate and a Kubernetes node-affinity guard.

**Monitoring (config, not deployed locally).**
- **SLOs:** 99.9% for shared stacks, 99.95% for dedicated, p95 < 400 ms ([`docs/operations.md`](docs/operations.md)).
- **Alert rules:** multi-window burn-rate alerts, latency, queue backlog, worker failures, unavailable replicas, PostgreSQL connections and backup age ([`gitops/observability/prometheus-rules.yaml`](gitops/observability/prometheus-rules.yaml)).
- **Runbooks:** [`docs/runbooks/`](docs/runbooks/).
- **Per-tenant visibility:** every object carries a `platform.io/tenant` label.

Locally, the rollout gates read the API's own `/metrics`, and `scripts/observe-scaling.sh` samples HPA, KEDA and queue state.

## Testing
| What | Command | Needs |
|---|---|---|
| Unit tests (Redis mocked) | `.venv/bin/python -m pytest` | Python venv |
| Lint | `shellcheck -S warning scripts/*.sh` · `actionlint` · `helm lint deploy/chart` | tools or their containers |
| IaC | see *Terraform usage* | Terraform |
| Deploy under load, rollbacks, 15x ratio, restore, drain, isolation | the `scripts/test-*.sh` and `scripts/backup-restore-postgres.sh` commands in *Operating it* | running kind cluster, about 3 GiB free RAM |

## Evidence
Index: [`evidence/submission-2026-11-04/README.md`](evidence/submission-2026-11-04/README.md). The four required scenarios:
- **Deploy under load:** [`deploy-under-load/`](evidence/submission-2026-11-04/deploy-under-load/). 36,001 requests at 150 rps during a digest rollout, 0 failed.
- **Automatic rollback:**
  - [`rollback-bad-release-metrics/`](evidence/submission-2026-11-04/rollback-bad-release-metrics/): the metric gate caught a 32% error rate and rolled back.
  - [`rollback-bad-release-readiness/`](evidence/submission-2026-11-04/rollback-bad-release-readiness/): pods never became Ready, so Helm rolled back; 0 failed requests.
- **15x load (ratio):** [`load-15x-ratio/`](evidence/submission-2026-11-04/load-15x-ratio/). 10 → 150 → 10 rps, 0 failed, 1,170/1,170 jobs completed.
- **Backup and restore:** [`backup-restore/`](evidence/submission-2026-11-04/backup-restore/). Restored into a new database; schema, row count and content MD5 identical.

Terminal recordings are in [`recordings/`](evidence/submission-2026-11-04/recordings/).

## Known limitations
Full list: [`limitations.md`](evidence/submission-2026-11-04/limitations.md).
- **Runtime environment:** all runtime tests ran on a **local single-node kind cluster**. No AWS, GCP or other cloud resources were provisioned.
- **15x load:** the test was a **ratio** (10 → 150 rps). The **2,250 rps peak was not tested**.
- **Application:** a **reference test harness** was used, not the assignment's black-box application, which wasn't supplied. Its startup migrations were not tested.
- **Delivery to a cluster:** CI promotes GHCR tags only; it doesn't deploy to any cluster. Argo CD, Argo Rollouts and Prometheus are configuration only.
- **Change request:** the second-cloud stack (US-West primary, US-East failover) is **documented only**: not provisioned, tested or released.

## Cleanup (local)
`kind delete cluster --name devops-assignment` removes the cluster and everything in it. Then `docker rm -f kind-registry` removes the local registry (check the name with `docker ps`). Restore drills leave `migration_demo_restore_<timestamp>` databases behind, by design; drop them with `psql` when no longer needed.
