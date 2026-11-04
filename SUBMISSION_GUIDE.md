# Submission guide

How to send this assignment to HR and the interview panel, and what must be disclosed. Everything listed here is in the public repository:
**https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform** (branch `main`).

## 1. Files to attach to the HR email
Attach these two PDFs. They are the only deliverables the assignment asks for as documents.

| # | File | What it is | Size limit met |
|---|---|---|---|
| 1 | `docs/pdf/architecture.pdf` | Architecture document: diagrams, 8 decisions with rejected alternatives, top 5 risks | 5 pages (max 5) |
| 2 | `docs/pdf/change-request-us.pdf` | Change request CR-001: second cloud, US-West primary, US-East failover | 1 page (one-page addendum) |

Everything else (code, IaC, pipelines, scripts, evidence) is shared as links. That keeps the logs in their original form.

## 2. Links to share
| What | Link |
|---|---|
| Repository (README is the landing page) | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform |
| Evidence index | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/evidence/submission-2026-11-04/README.md |
| Final submission report (requirement-to-evidence matrix) | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/evidence/submission-2026-11-04/FINAL_SUBMISSION_REPORT.md |
| Limitations (must be read together with the evidence) | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/evidence/submission-2026-11-04/limitations.md |
| Successful CI run #5 (build, scan, SBOM, sign, promote dev → staging → production) | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665 |
| CI workflow definition | https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/.github/workflows/ci.yml |

## 3. Where each deliverable is
| Assignment deliverable | Location in the repository |
|---|---|
| Git repository with README, IaC, pipelines and scripts | `README.md`; `infra/` (Terraform); `.github/workflows/` (pipelines); `scripts/`; `deploy/chart/` (Helm); `gitops/` |
| Architecture document (max 5 pages): diagram, ≥ 5 decisions with rejected alternatives, top 5 risks | `docs/pdf/architecture.pdf` (source `docs/architecture.md`): diagrams in §1, decisions in §5, risks in §6 |
| Evidence: deploy under load, automatic rollback, 15x load test, restore test | `evidence/submission-2026-11-04/` (index: `README.md`) |
| Change request (one-page addendum) | `docs/pdf/change-request-us.pdf` (source `docs/change-request-us.md`) |

## 4. Evidence for each required test
All four ran on a **local single-node kind cluster** with the **reference test harness**, not in a cloud. Each folder has `run.txt` (raw output of the exact command) plus supporting raw files; terminal recordings of the same runs are in `evidence/submission-2026-11-04/recordings/`.

| Required test | Evidence | Observed result |
|---|---|---|
| Deploy under load with no errors | `deploy-under-load/` (`run.txt`, `rollout.txt`, `k6-summary.json`, `endpoints.txt`, `pod-watch.txt`); recording `recordings/deploy-under-load.*` | Digest rollout during 150 rps (11:19:46–11:22:24 IST): 36,001 requests, **0 failed**, p95 2.91 ms; ready endpoints never below 5; 4/4 metric gates passed |
| Automatic rollback of a bad release (metric gate) | `rollback-bad-release-metrics/`; recording `recordings/rollback-bad-release-metrics.*` | Bad release (30% injected errors) passed probes; gate measured error rate 0.3224 and ran `helm rollback` 26 → 25 automatically. Clients saw 2,649 of 20,000 requests fail (13.2%) while it was live; this is expected and is the reason for the canary design |
| Automatic rollback of a bad release (readiness) | `rollback-bad-release-readiness/`; recording `recordings/rollback-bad-release-readiness.*` | New pods never became Ready; Helm rolled back automatically (revision 28 failed → 29 = 27). 0 of 15,000 requests failed; ready endpoints dipped to 4 (of 5) |
| 15x load test | `load-15x-ratio/` (`run.txt`, `scaling-timeline.txt`, `k6-summary.json`); recording `recordings/load-15x-ratio.*` | 10 → 150 → 10 rps (a 15x **ratio**): 35,099 requests, 0 failed, p95 4.03 ms; API 2 → 5 pods, workers 1 → 6; 1,170/1,170 jobs completed, 0 pending. **The 2,250 rps peak was not run.** |
| Restore test | `backup-restore/run.txt`; recording `recordings/backup-restore.*` | `pg_dump` → restore into a **new** database; schema, row count and content MD5 identical (2-row demo database). Dump SHA-256 `78fc3e4f…a2e44a` recorded; the dump file itself is gitignored |
| CI pipeline (supporting) | `ci-run.txt` | Run #5 green on commit `9d747ff`; one digest `sha256:5bd2b6b4…db0e3` promoted to dev, staging, production with manual approvals; signature and SBOM attestation re-verified |

## 5. Limitations you must disclose
State these in the email or the review, in these words or similar:
1. All runtime tests ran on a **local single-node Kubernetes (kind) cluster** on a laptop. **No AWS, GCP or other cloud resources were provisioned**; the Terraform is validated and unit-tested with a mocked provider but was never applied.
2. The 15x test demonstrated **10 → 150 requests per second** (a 15x ratio). The **2,250 rps peak was not tested**.
3. The application is a **reference implementation** I wrote to the black-box contract, **not the original black-box application**, which was not supplied. Its startup migrations were therefore not tested.
4. The second-cloud change request is **documented, not provisioned or released**.
5. CI run #5 tested commit `9d747ff`. Later commits change only documentation and evidence and were pushed with `[skip ci]`; CI promotes GHCR image tags, it does not deploy to a cluster.
6. Argo CD, Argo Rollouts and Prometheus/alerting are configuration only (not installed locally).
7. Known review findings that were not fixed in this submission (listed in `FINAL_SUBMISSION_REPORT.md` §5): IAM scope of the CI apply role, EKS public endpoint CIDR, and minor script hardening.

Suggested sentence: *"Everything runtime-related was proven on a local kind cluster with a reference app; cloud infrastructure is implemented as validated Terraform but not applied, and the 2,250 rps peak was not run. Each limitation is listed in `limitations.md`."*

## 6. How to check that HR can access everything
Do this before sending:
1. Open each link in section 2 in a **private/incognito window** while logged out of GitHub. Each must load without a sign-in prompt. (The repository and its Actions runs are public; job *logs* and run *artifacts* need a GitHub login, so don't point HR at those.)
2. From a terminal, every link should return HTTP 200:
   ```bash
   for u in https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform \
            https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665 \
            https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/evidence/submission-2026-11-04/README.md \
            https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/blob/main/docs/pdf/architecture.pdf; do
     curl -s -o /dev/null -w "%{http_code} $u\n" "$u"; done
   ```
3. Open both attached PDFs from the email draft and check page counts: 5 and 1.
4. Confirm `main` on GitHub shows the commit you expect: `git fetch && git status` should say *up to date with 'origin/main'*.
5. Don't edit the repository after sending. If something must change, mention it to HR, because the links point to `main`.
