# Final submission report

*Assignment:* Senior DevOps Assignment, "Cloud-Agnostic, Automated, Zero-Downtime Deployment Platform" (1-page PDF, used as the source of truth).
*Repository:* https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform (`main`).
*Report date:* 2026-11-04.

## 1. Verdict
**Ready for submission, as an honestly labelled local-only implementation.**

- All four deliverables in the PDF exist and were checked against the files.
- Three of the four required tests ran with zero failed requests and full raw evidence; the fourth (15x) ran as a ratio only.
- The CI pipeline is green end to end.
- Every gap is labelled in [limitations.md](limitations.md).

| Measure | Result |
|---|---|
| Deliverables present | **4 of 4** |
| Required evidence | **3.5 of 4**: the 15x test is a ratio (10 → 150 rps), not the 2,250 rps peak |
| Overall completion against the full brief | **≈ 85%** |

Basis for 85%: everything the brief asks to *design* is covered, and everything that can run on one laptop was run. Not executed:
- any cloud apply;
- the 2,250 rps peak;
- the black-box application and its startup migrations;
- Argo CD, Argo Rollouts and Prometheus in a cluster;
- the second-cloud change request.

## 2. Deliverables
| # | Deliverable (assignment PDF) | Where | Check performed | Status |
|---|---|---|---|---|
| 1 | Git repository with README, IaC, pipelines and scripts | [`README.md`](../../README.md), [`infra/`](../../infra/), [`.github/workflows/`](../../.github/workflows/), [`scripts/`](../../scripts/), [`deploy/chart/`](../../deploy/chart/) | Unit tests, lint, Helm, Terraform validate/test all pass ([submission-validation.txt](submission-validation.txt)); CI run #5 green ([ci-run.txt](ci-run.txt)) | **Completed and verified** (IaC validated, not applied) |
| 2 | Architecture document, max 5 pages: diagram, ≥ 5 decisions with rejected alternatives, top 5 risks | [`docs/pdf/architecture.pdf`](../../docs/pdf/architecture.pdf) | 5 pages (`pdfinfo`). Contents: 3 diagrams (request/data flow, CI/CD, runtime targets); 8 decisions with reason/benefit, rejected alternative and trade-off; 5 risks with impact, likelihood, mitigation and recovery | **Completed and verified** |
| 3 | Evidence: deploy under load with no errors, automatic rollback, 15x load test, restore test | this folder; index [README.md](README.md) | Raw outputs re-read; numbers below match the raw files | **Partially completed** (15x as ratio only) |
| 4 | Change request: second dedicated stack on a different cloud, US-West with US-East failover, one page | [`docs/pdf/change-request-us.pdf`](../../docs/pdf/change-request-us.pdf) | 1 page (`pdfinfo`) | **Completed and verified** as a document; the stack itself is **Documented but not executed** |

## 3. Required test evidence
All four tests ran on a **local single-node kind cluster** with the **reference test harness**. None ran in a cloud. Load came from k6 running inside the cluster.

| Test | Raw evidence | What it shows | Observed result | Status |
|---|---|---|---|---|
| **Deploy under load with no errors** | [deploy-under-load/run.txt](deploy-under-load/run.txt), [rollout.txt](deploy-under-load/rollout.txt), [endpoints.txt](deploy-under-load/endpoints.txt), [pod-watch.txt](deploy-under-load/pod-watch.txt), [k6-summary.json](deploy-under-load/k6-summary.json); recording `recordings/deploy-under-load.*` | Continuous 150 rps for 240 s. Digest rollout to revision 25: started 11:19:46 IST, Ready 11:20:43, four analysis steps passed by 11:22:24. Ready endpoints sampled every ~1 s | 36,001 requests, **0 failed**, p95 2.91 ms, max 59.75 ms; ready endpoints never below 5. **No interruption observed** in this test. Not a production zero-downtime claim (one node, no cloud load balancer) | Completed and verified (local) |
| **Automatic rollback: metric gate** | [rollback-bad-release-metrics/run.txt](rollback-bad-release-metrics/run.txt) and siblings; recording | Release with 30% injected errors passes probes (Gate 1, 11:25:00). Gate 2 step 1 measures error_rate 0.3224 > 0.01 → automatic `helm rollback` 26 → 25, complete 11:26:27 | Bad release detected and rolled back with no manual action. Clients saw 2,649 / 20,000 failed (13.2%) while it was live (expected; it motivates the canary design) | Completed and verified (local) |
| **Automatic rollback: readiness** | [rollback-bad-release-readiness/run.txt](rollback-bad-release-readiness/run.txt) and siblings; recording | Release pointing at a non-existent Redis; new pods never Ready; `helm --rollback-on-failure` reverts (revision 28 failed → 29 = 27) | 0 / 15,000 requests failed; ready endpoints dipped to 4 (of 5) and recovered | Completed and verified (local) |
| **15x load test** | [load-15x-ratio/run.txt](load-15x-ratio/run.txt), [scaling-timeline.txt](load-15x-ratio/scaling-timeline.txt), [k6-summary.json](load-15x-ratio/k6-summary.json); recording | Baseline 10 rps → 150 rps → 10 rps over 365 s, one job per 30 requests | 35,099 requests (avg 97.5 rps), **0 failed**, p95 4.03 ms; API 2 → 5 pods (local max), workers 1 → 6 on queue lag and back; **1,170 / 1,170 jobs completed, 0 pending**. **2,250 rps not run.** | **Partially completed**; 2,250 rps **Blocked** (cloud spend not approved) |
| **Backup and restore** | [backup-restore/run.txt](backup-restore/run.txt); recording | `pg_dump` (custom format) → local file with SHA-256 → restore into a **new** database → fingerprint comparison | Before and after: schema identical, rows 2 = 2, content MD5 `f9c4e0a9…b8c8` = same. Dump SHA-256 `78fc3e4f…a2e44a` re-verified today (file is gitignored, kept locally) | Completed and verified (local; 2-row demo DB, not RTO at scale) |

Failed and partial attempts are kept unchanged and listed in [limitations.md](limitations.md): deploy-under-load attempts 1–2, isolation attempt 1, KEDA retries, baseline-upgrade attempt 1, and CI runs #1–#2.

## 4. Requirement-to-evidence matrix ("Items to cover")
| Requirement | Implementation | Evidence | Status |
|---|---|---|---|
| Cloud-agnostic IaC; provider layer separate from platform and app | `infra/` provider roots → output contract → `infra/platform` → chart | `terraform validate` 7/7 roots, `terraform test` 4/4 ([submission-validation.txt](submission-validation.txt)) | Partially completed (validated, not applied) |
| Two targets (one cloud + local kind) | kind: exercised; AWS: Terraform | All runtime folders; [terraform-validation.txt](terraform-validation.txt) | Partially completed (kind run; AWS not applied) |
| List what is not portable | `docs/architecture.md` §1, `infra/README.md` | Document | Completed and verified |
| Empty account → running platform, no console steps | bootstrap → live → platform → Argo CD | `infra/README.md` | Documented but not executed (code exists) |
| Remote state, drift detection, secrets manager | S3 native locking, nightly `terraform plan`, RDS-managed secret + ESO | `infra/bootstrap`, `drift-detection.yml` | Documented but not executed (code exists; drift job skipped until AWS exists) |
| Build once, scan, sign, promote same digest dev → staging → production | `ci.yml`, `promote.yml` | CI [run 41810479665](https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665), [ci-run.txt](ci-run.txt): one digest on all three tags, signature/attestation re-verified | Completed and verified |
| Required approvals for staging and production | GitHub Environments, required reviewer | Approvals recorded in [ci-run.txt](ci-run.txt) §A3 | Completed and verified |
| Gates based on real metrics | Local: `scripts/gated-rollout.sh`; cloud: Argo Rollouts AnalysisTemplate | rollback-bad-release-metrics | Partially completed (local gates tested; cloud analysis is config only) |
| API and worker deployment strategy, traffic steps, gating metrics, automatic rollback | API canary 10/25/50/100% (design), rolling + analysis locally; worker rolling with drain | `docs/architecture.md` §2; deploy-under-load, rollback-* | Partially completed (canary not executed) |
| GitOps pull vs push decision | Argo CD ApplicationSet (design); push used locally | `gitops/argocd/`, decision 3 | Documented but not executed |
| Rollout order: shared → dedicated rings → regions, halt on failure | `gitops/fleet.yaml`, `scripts/fleet-rollout.sh` | [fleet-rollout-good/](fleet-rollout-good/), [fleet-rollout-halt/](fleet-rollout-halt/) | Completed and verified (local) |
| Graceful shutdown, probes, disruption budgets | Chart settings | deploy-under-load; Docker smoke test shows graceful shutdown ([docker-smoke.txt](docker-smoke.txt)) | Completed and verified (local) |
| Worker draining (jobs up to 60 s) | SIGTERM drain, 75 s grace, XACK after completion | [worker-drain/run.txt](worker-drain/run.txt) | Completed and verified (local) |
| Safe DB migrations (expand/contract, rollback after a migration) | SQL demo + policy + runbook | `docs/database-migrations.md`, `../database-migration-report.md` | Partially completed (SQL demo ran; black-box startup migrations **Blocked**, app not supplied) |
| Autoscale 15x in < 5 min and back without dropping jobs; queue depth for workers | HPA + KEDA on stream lag | load-15x-ratio | Partially completed (ratio only) |
| Capacity maths and database limits | `docs/architecture.md` §3 | Document | Completed and verified (as analysis) |
| Shared stack + dedicated tenant stacks from one template | Chart + tenant values; `modules/aws-stack` instances | [tenant-onboarding/](tenant-onboarding/), `infra/live/aws/` | Partially completed (Kubernetes layer run; cloud stacks not applied) |
| New tenant in < 30 min from one reviewed change | One values file (+ one Terraform root for cloud) | tenant-onboarding: 16 s (Kubernetes layer) | Partially completed (cloud stack time estimated at 20–25 min, not measured) |
| EU data never leaves the EU | Terraform validation, onboarding policy gate, node-affinity guard | [isolation-residency/](isolation-residency/) 9/9; `terraform test` | Partially completed (local + mocked provider) |
| SLOs, alerts, per-tenant visibility | `docs/operations.md`, `gitops/observability/prometheus-rules.yaml`, tenant labels | Config only | Documented but not executed |
| Runbooks | `docs/runbooks/` (5) | Documents | Completed and verified (as documents) |
| Backups and a restore test | `scripts/backup-restore-postgres.sh` | backup-restore | Completed and verified (local) |
| Monthly cost (steady and peak), 90-day roadmap | `docs/cost-estimate.md`, `docs/90-day-roadmap.md` | Documents (list-price estimate) | Completed and verified (as documents) |
| Change request: second cloud, US-West + US-East failover | `docs/change-request-us.md` | 1-page PDF | Documented but not executed |
| Change request "released after 24 hours" | Release gate written into the CR | CR "Release gate" | Not applicable (nothing released) |
| Black-box application deployed without rewrite | Reference harness to the same contract | `docs/architecture.md` scope note | **Blocked** (application not supplied) |
| 2,250 rps peak test | `docs/cost-estimate.md` sizing | none | **Blocked** (needs cloud capacity and spend approval) |

## 5. Review findings not fixed in this submission
These come from a code review on 2026-11-04. They were left unchanged on purpose. Fixing them means changing code, which needs a new CI run and approvals, and the Terraform has never been applied. They should be fixed **before any cloud apply**.

| Area | Finding | Location |
|---|---|---|
| IAM (significant) | The CI apply role may create, modify and pass IAM roles and policies on `*`, so it is a privilege-escalation path. The code acknowledges this; a permissions boundary is the stated next step. `secretsmanager:*`/`kms:*` on `*` are also broad. No workflow uses this role yet | `infra/bootstrap/aws-state/github-oidc.tf` |
| IAM (minor) | The plan role can read `*/redis-auth-*` secrets, and its trust includes `pull_request` (unused today) | same file |
| Network (significant, documented TODO) | EKS public API endpoint allows `0.0.0.0/0` (IAM auth still required); no VPC flow logs | `infra/live/aws/*/main.tf` |
| State (documented) | The Grafana admin password lives in `infra/platform` state (encrypted remote state on AWS) | `infra/platform/main.tf` |
| CI (minor) | CI validates 6 Terraform roots, not `modules/aws-stack`, and doesn't run `terraform test`; both run locally | `.github/workflows/ci.yml` |
| Scripts (minor) | No script checks the current kubectl context. `test-worker-drain.sh` has two wait loops with no timeout. `check-tools.sh`, `local-cluster.sh` and `test-rollout-availability.sh` have no header comment. There is no standalone cleanup or manual-rollback script; cleanup and rollback commands are in the README | `scripts/` |

Confirmed fine: all 17 scripts are executable in Git and pass `bash -n` and shellcheck; there are no hard-coded secrets. The workflows were confirmed for:
- least-privilege permissions;
- actions pinned to full SHAs;
- pull requests never push or sign;
- exactly one build;
- the Trivy gate;
- SBOM;
- keyless sign and attest;
- verification before every promotion;
- the promoted-digest equality check.

## 6. Final validation (this pass)
| Check | Result | Raw output |
|---|---|---|
| Assignment PDF inspected | 1 page; 4 deliverables and 9 "items to cover" mapped above | `~/Downloads/Senior_DevOps_Assignment.pdf` (not in repo) |
| Unit tests | 14 / 14 pass | [submission-validation.txt](submission-validation.txt) |
| Python compile, shellcheck, `bash -n`, actionlint | all exit 0 | same |
| Helm | lint OK; 7 / 7 environment and tenant renders; server-side dry-run on kind OK | same |
| Terraform | `fmt -check` clean; 7 / 7 roots `validate`; `terraform test` 4 / 4 (mocked provider) | same |
| PDFs | architecture 5 pages (≤ 5); change request 1 page | same |
| Raw evidence | `evidence/raw/SHA256SUMS.txt` 8 / 8 OK; backup dump SHA-256 matches; no tracked raw evidence file modified | same |
| Docker image | CI-built digest runs: `/healthz` 200, `/readyz` 200, job accepted, processed and ACKed, graceful stop | [docker-smoke.txt](docker-smoke.txt) |
| Markdown links | all relative links in tracked Markdown resolve; public URLs return 200 anonymously | end of [submission-validation.txt](submission-validation.txt) |
| CI | run #5 (41810479665) green on `9d747ff`; tags, signature, attestation re-verified | [ci-run.txt](ci-run.txt) |
| Overall | **0 failed checks** | |

## 7. What changed in this pass
- **README:** added sections for overview and objectives, architecture overview, technology stack, Docker build and run, Kubernetes deployment, Terraform usage, CI/CD pipeline, security and monitoring, testing, evidence, known limitations and cleanup. CI references now point to run #5.
- **Architecture document:**
  - added an objectives paragraph and a request/data-flow diagram;
  - CI reference updated to run #5;
  - two claims corrected: the Grafana state exception, and the apply role, which no workflow uses yet.
  - Re-rendered; still 5 pages.
- **`infra/README.md`:** corrected the plan/apply role description.
- **New files:**
  - `SUBMISSION_GUIDE.md`
  - this report
  - `submission-validation.txt`
  - `docker-smoke.txt`
- **Unchanged:**
  - code, chart, Terraform, scripts and workflows, so CI run #5 still covers all executable content;
  - every raw evidence file.
