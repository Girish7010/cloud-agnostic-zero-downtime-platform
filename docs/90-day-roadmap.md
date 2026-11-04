# 90-day roadmap

Starting point (4 Nov 2026), from the README status matrix:
- **Proven on kind:** platform mechanics (gated rollouts, rollback, drain, KEDA, tenancy, backup/restore).
- **Validated but not applied:** AWS IaC.
- **Missing:** the black-box app, and any cloud load test.

Each phase ends with evidence, not documents.

| Days | Goal | Deliverables | Exit criteria (evidence) |
|---|---|---|---|
| **1–10** | Integrate the real application | Obtain the black-box images; map env vars, DB URL and migration behaviour; confirm `rediss://` TLS support and idempotency of jobs; replace the reference harness in `deploy/environments/*` | Real app passes the probe contract on kind; startup-migration behaviour documented with N-1 test |
| **11–25** | AWS foundation (dev + staging) | Apply `bootstrap/aws-state`, then `live/aws/shared-eu` as staging; platform layer; Argo CD + ApplicationSet; ESO wiring; required reviewers on GitHub environments; least-privilege DB role; RDS Proxy | `terraform plan` clean (drift job green); first image promoted by digest dev→staging via Argo CD; cosign verify enforced at admission (Kyverno/policy-controller) |
| **26–40** | Progressive delivery in cloud | Argo Rollouts canary with Prometheus AnalysisTemplate; tenant ring sync; migration Job with advisory lock; snapshot gate before contract releases | Bad-release canary aborts at 10% with measured exposure; migration rehearsal (expand→backfill→contract) on a prod-sized copy |
| **41–55** | Scale and capacity | 2,250 rps k6 from a distributed runner in-region; measure per-pod rps, job duration distribution, DB connections; tune HPA/KEDA/overprovisioning; Karpenter evaluation | **15x within 5 min with p95 < 400 ms and 0 dropped jobs**, recorded; capacity plan updated with measured numbers |
| **56–70** | Operations | kube-prometheus-stack in cloud; SLO burn-rate alerts live; per-tenant Grafana dashboards; on-call rota; runbook game days (AZ failure, Redis failover, bad migration) | Restore drill of RDS PITR into a new instance, timed (RTO) and validated; alert → runbook path exercised |
| **71–80** | Production + dedicated tenants | Production stack; onboard the first dedicated EU tenant through the one-PR flow; residency audit (regions, backups, logs) | Tenant onboarded in < 30 min end-to-end (measured); residency audit report |
| **81–90** | Hardening and cost | Savings Plans, Graviton, CDN for egress; permissions boundaries; SBOM/vuln SLAs; US change request (second cloud) design review and pilot | Monthly cost within $9k steady (billing data); security review sign-off; CR go/no-go |

**Ownership:**
- **Platform team:** layers 1–2, pipeline, SLO tooling.
- **Application team:** black-box compatibility (migrations, idempotency, TLS).
- **Tenant operations:** onboarding and ring promotion approvals.

**Top dependency:** access to the real application and its migration behaviour (day 1).
