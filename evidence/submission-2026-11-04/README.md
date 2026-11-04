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
| 15 | CI pipeline run | GitHub Actions (on push) | `.github/workflows/ci.yml` | **see the Actions tab; recorded in [ci-run.txt](ci-run.txt) after push** |

Earlier evidence from 3 November is in `../` (rollout 60/60, the Helm worker rollback 16→17, the migration demo). The ignored `.log` originals are preserved byte-identical as `../raw/*.txt`, with SHA-256 sums in `../raw/SHA256SUMS.txt`.
