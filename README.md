# Cloud-Agnostic, Automated, Zero-Downtime Deployment Platform
<img width="1216" height="826" alt="image" src="https://github.com/user-attachments/assets/2a90775b-2959-44d1-9533-8a8e79329289" />


A deployment platform for a stateless API plus a Redis-queue worker, backed by PostgreSQL and Redis:
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

## Deliverables
| Deliverable | Location |
|---|---|
| Architecture document (≤ 5 pages: diagram, 8 decisions with rejected alternatives, top 5 risks, capacity, failure modes) | [`docs/architecture.md`](docs/architecture.md) |
| Evidence (deploy under load, automatic rollback, 15x-ratio load, restore, drain, tenancy) | [`evidence/submission-2026-11-04/README.md`](evidence/submission-2026-11-04/README.md) |
| Change request: second cloud, US-West primary / US-East failover (1 page) | [`docs/change-request-us.md`](docs/change-request-us.md) |
| Cost estimate (steady/peak) · 90-day roadmap | [`docs/cost-estimate.md`](docs/cost-estimate.md) · [`docs/90-day-roadmap.md`](docs/90-day-roadmap.md) |
| Operations (SLOs, alerts, backups) · runbooks | [`docs/operations.md`](docs/operations.md) · [`docs/runbooks/`](docs/runbooks/) |
| Review preparation | [`docs/review-prep.md`](docs/review-prep.md) |

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
| Build once, scan, SBOM, sign, promote same digest | Implemented; **runs on push to main** (check the Actions run) | `.github/workflows/ci.yml`, `promote.yml` |
| Deploy by immutable digest | Tested-local (local OCI registry) | `deploy/environments/local.yaml` |
| Approval gates | Implemented (GitHub environments; reviewers must be set in repo settings) | `ci.yml` |
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

## Quick start (local kind)
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

## Cloud (not applied, needs approval for spend)
See [`infra/README.md`](infra/README.md): `bootstrap/aws-state` → `live/aws/shared-eu` → `platform` → Argo CD. Review `terraform plan` and [`docs/cost-estimate.md`](docs/cost-estimate.md) before any `apply`.

## Security notes
- No secrets in Git or Terraform state. The one exception, the documented local demo, is a Kubernetes Secret created out of band and never committed.
- CI uses OIDC and `GITHUB_TOKEN` only. All actions are pinned to commit SHAs.
- Containers run as UID 1000 with a read-only root filesystem, all capabilities dropped and seccomp `RuntimeDefault`.
