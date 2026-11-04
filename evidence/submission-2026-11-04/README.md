# Evidence: 4 November 2026 (local kind cluster)

- **Environment:** Ubuntu laptop, 8 CPUs, 6.9 GiB RAM (swap ~95–100% used by host processes); kind 0.33.0 single node (`devops-assignment`), containerd 2.3.4; Helm 4.3.0; k6 2.3.0 running **in-cluster** against the ClusterIP Service.
- **App:** **reference test harness** image (not the black-box app), deployed **by digest** from a local OCI registry (`localhost:5001`).
- **Times:** host clock is IST (UTC+5:30); pod log timestamps are UTC.
- **Raw output:** each folder has `run.txt` (raw stdout of the exact command) plus supporting raw files. Terminal recordings of the same runs are in `recordings/`; replay one with `scriptreplay --timing=recordings/<name>.timing recordings/<name>.typescript`.
- **Honesty:** failed attempts are kept and listed in [limitations.md](limitations.md).

| # | Assignment evidence | Folder | Command | Result |
|---|---|---|---|---|
| 1 | **Deploy under load with no errors** | [deploy-under-load/](deploy-under-load/) | `scripts/test-deploy-under-load.sh deploy-under-load PROFILE=constant RATE=150 DURATION=240s JOB_EVERY=150 MAX_FAIL_RATE=0 -- -f deploy/environments/local.yaml --set api.image.digest=<v5> ...` | v4→v5 digest rollout during 150 rps: `{"requests":36001,"failed_count":0,"p95_ms":2.91}`; 4/4 metric-gate steps PASS; ready endpoints never < 5 |
| 2a | **Automatic rollback of a bad release (metrics)** | [rollback-bad-release-metrics/](rollback-bad-release-metrics/) | same, `--set-json api.extraEnv=[FAULT_ERROR_RATE=0.3]` | probes green; gate step 1 measured error_rate 0.3224 → automatic `helm rollback` 26→25 within 31 s of Ready. Client impact: `{"requests":20000,"failed_count":2649}` (13.2%, expected) |
| 2b | **Automatic rollback (readiness)** | [rollback-bad-release-readiness/](rollback-bad-release-readiness/) | same, `--set api.redisUrl=redis://does-not-exist:6379/0` | new pods never Ready → Helm rollback-on-failure (rev 28 failed → 29 = 27); `{"requests":15000,"failed_count":0}` |
| 3 | **15x load test** (ratio only) | [load-15x-ratio/](load-15x-ratio/) | `scripts/test-15x-ratio.sh` (10→150→10 rps, 1 job per 30 req) | `{"requests":35099,"failed_count":0,"p95_ms":4.03,"jobs_accepted":1170}`; API HPA 2→5 (capped at local max), KEDA workers 1→6 on stream lag, back to 2/1; **1,170/1,170 jobs completed, pending 0**. **2,250 rps NOT run.** |
| 4 | **Restore test** | [backup-restore/](backup-restore/) | `scripts/backup-restore-postgres.sh` | pg_dump → restore into a NEW DB; schema, row count, content MD5 identical (2-row demo DB) |
| 5 | Worker drain (60 s jobs) | [worker-drain/](worker-drain/) | `scripts/test-worker-drain.sh` | 45 s job interrupted at 6 s: completed + XACKed by old pod, exited after 41 s (< 75 s grace); post-SIGTERM job went to the new pod; pending 0, lag 0 |
| 6 | Tenant onboarding | [tenant-onboarding/](tenant-onboarding/) | `scripts/onboard-tenant.sh acme-eu && ... globex-eu` | 16 s each (k8s layer) from one file |
| 7 | Fleet rings + halt | [fleet-rollout-good/](fleet-rollout-good/), [fleet-rollout-halt/](fleet-rollout-halt/) | `scripts/fleet-rollout.sh ...` | good v6: ring 0→1→2 all gates PASS; bad: ring 0 failed (27.4% errors) → rolled back → **fleet halted**, rings 1–2 untouched |
| 8 | Isolation + EU residency | [isolation-residency/](isolation-residency/) | `scripts/test-isolation-residency.sh` | 9/9 PASS (policy gate, scheduler guard, NetworkPolicy with positive controls) |
| 9 | Queue autoscaler install | [keda-install/](keda-install/) | helm install KEDA 2.21.0 | deployed (first attempt timed out; ScaledObject attempt 1 rolled back by a DNS bug, since fixed) |
| 10 | Baseline upgrade to chart 0.2.0 | [baseline-upgrade-attempt1-FAILED.txt](baseline-upgrade-attempt1-FAILED.txt), [baseline-upgrade-attempt2.txt](baseline-upgrade-attempt2.txt) | helm upgrade | attempt 1 failed (SSA conflicts), API stayed available; attempt 2 deployed rev 20 |
| 11 | Unit tests, lint | [test-results.txt](test-results.txt) | pytest, compileall, shellcheck, actionlint | 14/14 pass (Redis mocked), no lint findings |
| 12 | Helm validation | [helm-validation.txt](helm-validation.txt) | helm lint/template per env + server dry-run | pass |
| 13 | Terraform validation | [terraform-validation.txt](terraform-validation.txt) | fmt/init -backend=false/validate per root, `terraform test` | 7/7 roots valid; 4/4 residency tests (mocked AWS provider) |
| 14 | Environment audit | [environment-audit.txt](environment-audit.txt) | tool versions, cluster, AWS read-only resource counts | no AWS compute/DB resources exist |
| 15 | **CI pipeline run (final)** | [ci-run.txt](ci-run.txt) · [run 41810479665](https://github.com/Girish7010/cloud-agnostic-zero-downtime-platform/actions/runs/41810479665) (#5) | `.github/workflows/ci.yml` on push of `9d747ff` | **all 5 jobs green**: verify → one build → Trivy 0 fixable CRITICAL/HIGH → CycloneDX SBOM → keyless sign + attest → dev, staging and production (the last two manually approved) all on `sha256:5bd2b6b4…db0e3`. Tag digests, signature, attestation and the certificate's commit binding (`9d747ff`) rechecked from this laptop with cosign v3.1.3. Earlier runs: #3 41804504092 (`2eb6bad`) and #4 41808718144 (`9e04255`) green; #1 41787637662 and #2 41798284612 **failed** (scanner installer exit 6), recorded in [limitations.md](limitations.md). |
| 16 | Final local validation | [final-validation.txt](final-validation.txt) | pytest, compileall, shellcheck, actionlint, Helm lint/render/server dry-run, Terraform fmt/init/validate (7 roots) + `terraform test`, PDF page counts, raw-log SHA-256 | **35/35 steps exit 0**; 14/14 tests; 4/4 Terraform tests; architecture 5 pages, CR 1 page; raw logs unchanged. The full run was on `2eb6bad` plus the docs/evidence tree later committed as `9d747ff`. The addendum re-checks `9d747ff`: no code/IaC/workflow path changed, 14/14 tests, page counts, raw-log and backup-dump SHA-256, **0 failed**. Helm, Terraform and lint weren't re-run locally (CI run #5 ran them on `9d747ff`). |
| 17 | Submission validation (final) | [submission-validation.txt](submission-validation.txt) | same checks as row 16, re-run on the submission tree, plus Markdown link and public-URL checks | **0 failed**; see the file's summary lines |
| 18 | Docker smoke test of the CI-built image | [docker-smoke.txt](docker-smoke.txt) | `docker run` of `sha256:5bd2b6b4…db0e3` with Redis | `/healthz` 200, `/readyz` 200, job accepted (202), processed and ACKed, graceful stop |

**Final report and requirement matrix:** [FINAL_SUBMISSION_REPORT.md](FINAL_SUBMISSION_REPORT.md). **How to submit:** [../../SUBMISSION_GUIDE.md](../../SUBMISSION_GUIDE.md).

## Requirement-to-evidence matrix (assignment PDF deliverables)

Statuses: **Completed** · **Partially completed** · **Documented but not executed** · **Blocked** · **Not applicable**. *Completed* means checked against the raw output or rendered file listed, not just that a document exists. Every runtime result is from a **local single-node kind cluster** running the **reference harness**, not the black-box app.

| Assignment requirement | Implementation | Evidence | Status |
|---|---|---|---|
| Git repository | `github.com/Girish7010/cloud-agnostic-zero-downtime-platform`, `main` | Commit history; [final-validation.txt](final-validation.txt) | Completed |
| README, IaC, pipelines, scripts | `README.md`, `infra/` (7 Terraform roots), `.github/workflows/`, `scripts/`, `deploy/chart` | [final-validation.txt](final-validation.txt): lint, validate, `terraform test` · CI: [ci-run.txt](ci-run.txt) | Completed: static checks pass locally, and the final CI run 41810479665 (#5, commit `9d747ff`) is green end to end (it promotes GHCR tags; no cluster deploy). AWS apply: **Blocked** (no spend approved) |
| Architecture document ≤ 5 pages | `docs/architecture.md` → `docs/pdf/architecture.pdf` | 5 pages (rendered by `scripts/render-docs.sh`, counted with `pdfinfo`) | Completed |
| Architecture diagram | Two Mermaid diagrams (delivery; runtime targets), labelled tested / implemented / design | `architecture.pdf` page 1 | Completed |
| ≥ 5 decisions with rejected alternatives | 8 decisions, each with reason, rejected alternative and trade-off | `architecture.md` §5 | Completed |
| Top five risks | R1–R5 with impact, likelihood, mitigation and recovery, plus a failure-mode table | `architecture.md` §6 | Completed |
| Deploy under load with no errors | `scripts/test-deploy-under-load.sh`: in-cluster k6 at 150 rps during a v4→v5 **digest** rollout (11:19:46–11:22:24 IST) | [deploy-under-load/](deploy-under-load/): 36,001 requests, **0 failed**, p95 2.91 ms, ready endpoints never < 5, 4/4 gates PASS | Completed (**local single-node kind**, not multi-node cloud) |
| Automatic rollback of a bad release | `scripts/gated-rollout.sh`: gate 1 readiness, gate 2 metric analysis; deliberately bad releases | [rollback-bad-release-metrics/](rollback-bad-release-metrics/) (error rate 0.3224 → `helm rollback` 26→25), [rollback-bad-release-readiness/](rollback-bad-release-readiness/) (rev 28 failed → 29 = 27, 0 of 15,000 failed) | Completed (local) |
| 15x load test | `scripts/test-15x-ratio.sh`: 10 → 150 → 10 rps (a 15x **ratio**), HPA and KEDA | [load-15x-ratio/](load-15x-ratio/): 35,099 requests, 0 failed, p95 4.03 ms, 1,170/1,170 jobs; API 2→5, workers 1→6 | **Partially completed**: a 15x ratio passed. The PDF's 2,250 rps peak is **Blocked**: it needs cloud capacity and spend approval (`docs/cost-estimate.md`). |
| Restore test | `scripts/backup-restore-postgres.sh`: `pg_dump`, then restore into a **new** DB | [backup-restore/run.txt](backup-restore/run.txt): schema, rows and content MD5 identical. The dump's SHA-256 was rechecked on 2026-11-04 and matches. | Completed (procedure on a 2-row demo DB; not RTO at scale) |
| Second dedicated cloud stack | GCP `gcp-stack` design behind the same output contract | `docs/change-request-us.md` | Documented but not executed |
| US-West primary / US-East failover | us-west1 primary, us-east4 warm standby, RPO/RTO, failover and failback | `docs/change-request-us.md` | Documented but not executed |
| One-page change request | `docs/change-request-us.md` → `docs/pdf/change-request-us.pdf` | 1 page (`pdfinfo`) | Completed |
| 24-hour release condition | Release gate: CAB approval, go-live no earlier than 24 h after approval, game day passed | `change-request-us.md` "Release gate" | Completed as a written gate. The release itself is **Not applicable** today: the CR is future work and nothing was released. |

**Note on row 3 (API replica count at the end of the 15x run).** `load-15x-ratio/run.txt` prints `final: api=2`, but the `kubectl get hpa` output directly below shows `REPLICAS 3`, and the last `scaling-timeline.txt` sample (12:06:34) also shows 3. These read different fields:
- `final: api=` is the Deployment's `.status.replicas`, which drops as soon as the HPA scales down;
- the timeline uses `.status.readyReplicas`, which still counts the pod that is terminating;
- the HPA `REPLICAS` column is the HPA's own `currentReplicas`, which is refreshed on its sync loop (15 s by default).

So at 12:06:39 the scale-in to 2 had been decided, but the third pod hadn't finished terminating. This is the most likely reading; it wasn't captured directly. A read-only check during the audit on 2026-11-04 showed the HPA at 2 replicas. The raw log is unchanged.

Earlier evidence from 3 November is in `../` (rollout 60/60, the Helm worker rollback 16→17, the migration demo). The ignored `.log` originals are preserved byte-identical as `../raw/*.txt`, with SHA-256 sums in `../raw/SHA256SUMS.txt`.
