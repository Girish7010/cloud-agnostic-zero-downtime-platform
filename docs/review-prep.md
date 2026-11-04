# 60-minute review: preparation sheet

Short, defensible answers. Every "tested" claim points to a file in `evidence/submission-2026-11-04/`.

## Opening (2 min)
"I built the platform mechanics and proved them on a local kind cluster with a reference app that honours the black-box contract. The AWS IaC is complete and validated but intentionally not applied, to avoid spend. Here is what I ran, what I only designed, and what I'd do next."

## Likely questions

**Q: Is the app you deployed the black box?**
No. It's a test harness I wrote, implementing only the contract: port 8080, `/healthz`, `/readyz`, `/metrics`, and a Redis worker. The chart and platform depend only on that contract. Swapping in the real image means changing the repository and digest in `deploy/environments/*.yaml`, plus its env vars.

**Q: What does "cloud-agnostic" mean here, honestly?**
The platform and application layers (Helm chart, KEDA, Argo, Prometheus rules) are identical on kind and EKS. The provider layer is deliberately provider-specific, behind one output contract. Non-portable pieces are listed in `docs/architecture.md` §1. Only two targets exist: kind (runtime-tested) and AWS (validated only).

**Q: How do you know it's the same artifact in production?**
The pipeline builds once (`build` job), captures the registry digest, signs it with keyless Cosign, and attests the SBOM. Each promotion job runs `cosign verify` with the workflow identity regex, retags with `imagetools create`, and asserts the promoted digest equals the built one. Nothing rebuilds. Locally I deployed by `@sha256:` from a local registry as well.

**Q: Where are the metric gates?**
- **Locally:** `scripts/gated-rollout.sh`. It reads real per-pod counters (`http_requests_total`, latency histogram) from the new pods every 15 s, and fails on more than 1% 5xx or more than 5% of requests slower than 400 ms. Too little traffic counts as inconclusive, which fails safe.
- **Cloud design:** an Argo Rollouts AnalysisTemplate querying Prometheus (`gitops/rollouts/api-canary.yaml`).
- **GitHub:** the gates there are tests, scan, signature verification and required reviewers. A runner can't see cluster metrics.

**Q: Show me automatic rollback.**
Two tests:
- **Metrics-detected bad release:** 30% injected 500s, probes green. The gate failed at step 1 with an error rate of 0.32 and rolled back.
- **Readiness-failing release:** wrong Redis URL. Helm's `--rollback-on-failure` rolled back, and k6 saw 0 of 15,000 requests fail.

There was also a ring-0 failure that halted the fleet.

**Q: The bad release produced 13% client errors. Is that zero downtime?**
No, and I say so. A rolling update exposes all traffic, so the gate limited the exposure to about 87 s. That measurement is exactly why the production design is a 10% canary. "Zero downtime" applies to good releases: 36,001 requests at 150 rps, 0 failed, during a digest change.

**Q: Why did your first deploy-under-load runs fail?**
- **Run 1:** the HPA scaled 2→5 pods during analysis, and summing counters across a changing pod set gave a negative delta. I fixed it with per-pod deltas.
- **Run 2:** my load ended before the analysis did, so the result was inconclusive and the gate failed safe.

Both runs still had 0 client errors through the rollout and rollback. I kept both logs.

**Q: How does the worker avoid losing jobs?**
- **Drain:** SIGTERM stops new reads, the current job finishes, it's XACKed, and the pod exits. The grace period is 75 s against a 60 s job maximum.
- **Proof:** a 45 s job was interrupted 6 s in; the old pod finished it, acknowledged it and exited in 41 s. A second job went to the new pod, and pending was 0.
- **Crash case:** delivery is at-least-once, reclaimed after 120 s, with a done-marker making redelivery idempotent. The real black-box worker must also be idempotent; that's a stated dependency.

**Q: Why KEDA rather than HPA for workers?**
Jobs are I/O-bound, so CPU doesn't reflect backlog; stream lag does. I measured KEDA scaling workers on Redis Streams lag locally and returning them to 1 without losing a job (`load-15x-ratio`).

**Q: Did you test 15x?**
- **What ran:** a 15x *ratio* on the laptop (10 → 150 rps), with HPA and KEDA scaling.
- **What didn't:** 2,250 rps. It needs cloud capacity and I chose not to spend without approval.
- **Capacity plan:** 20 API pods and about 72 workers at peak, which fits 8 of max 12 m6i.xlarge.
- **Main sensitivity:** average job duration.

**Q: Can it reach 15x in under 5 minutes?**
- **API:** the HPA allows +100% per 15 s, so 3→20 pods takes about 1.5–2 minutes, and the minimum nodes already have the vCPU.
- **Workers:** may need new nodes, about 2–3 minutes with the cluster-autoscaler, plus an overprovisioning pod.
- **Unproven:** at 2,250 rps.

**Q: Database connections at peak?**
About 354 (20×10 API + 72×2 workers + 10 admin) against a `max_connections` cap of 400, alerting at 80%. Beyond that, RDS Proxy or PgBouncer.

**Q: Migrations run on startup and are not backward compatible. How do you roll back?**
N-1 compatibility is mandatory, with expand/backfill/contract. Contract ships separately, approved and preceded by a snapshot. Rolling back before contract means redeploying the old digest. After contract, the old image can't bring data back, so it's a forward-fix or a PITR restore into a new instance. The backup/restore procedure was tested locally (checksum-identical).

**Q: How is EU data kept in the EU?**
1. Terraform validation plus a precondition on the real provider region; `terraform test` has 4/4 cases including rejection of EU in us-east-1.
2. The onboarding policy gate rejected an EU tenant declaring us-east-1 (tested).
3. Node affinity on `topology.kubernetes.io/region` kept an EU-pinned pod Pending on a non-EU node (tested).

On top of that, there's no cross-region backup for EU stacks, and telemetry is stored in-region. Global services and support access remain a residual risk.

**Q: Tenant isolation?**
- Each dedicated tenant has its own cloud stack (VPC, EKS, RDS, Valkey, state key).
- Within a cluster: a namespace per tenant with quota and LimitRange, Pod Security baseline, NetworkPolicies, and a separate ServiceAccount with no token automount.
- Tested 9/9, including positive controls so "blocked" isn't a broken probe. My first run had an invalid control, and I kept that log.

**Q: New tenant in under 30 minutes?**
- **Local:** one file and one script run, 16 s for the Kubernetes layer.
- **Cloud:** a dedicated stack is an estimated 20–25 minutes (EKS and RDS created in parallel). That's an estimate, not a measurement, so the mitigation is a warm pool.

**Q: Why GitOps pull, when your demo pushes?**
Pull removes cluster credentials from CI and self-heals drift. I didn't run Argo CD on the 6.9 GiB laptop alongside the tests, so the local demo uses the same values through `scripts/fleet-rollout.sh`. The ApplicationSet with ring-ordered RollingSync is in `gitops/argocd/`.

**Q: Remote state and drift?**
An S3 bucket with versioning, KMS and S3 native lock files (`use_lockfile`, no DynamoDB). Each stack has its own state key. A nightly `plan -detailed-exitcode` runs through the OIDC read-only role; exit code 2 means drift and fails the job. It isn't executed yet, because no stack exists.

**Q: Secrets?**
RDS manages its master password in Secrets Manager. The Redis token is ephemeral and write-only. External Secrets syncs both into Kubernetes. No secrets are in Git or state, except the documented Grafana and kind exceptions. CI uses OIDC only.

**Q: Cost?**
About $8.2k steady and $14.6k peak month, against $9k and $16k. Peak egress is the biggest lever, and each extra dedicated tenant is about $1.5k. These are list-price estimates, not verified in the calculator. The US change request adds about $2.1k, which breaches the steady budget unless offset.

**Q: What would you do next?**
Real app integration (migrations, idempotency, TLS), then AWS staging apply with Argo CD, then the 2,250 rps test. See `docs/90-day-roadmap.md`.

## Things to admit up front
- Reference app, not the black box.
- No cloud resources, so 2,250 rps, the cloud canary and cloud drift detection are not executed.
- The GitHub Actions pipeline's first real run happens on this push; check its result before the review.
- Argo CD, Argo Rollouts and kube-prometheus-stack are configured, not running.
- The local Redis and Postgres are single-instance.
