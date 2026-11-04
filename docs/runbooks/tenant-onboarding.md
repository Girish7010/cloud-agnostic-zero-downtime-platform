# Runbook: onboard a tenant (target < 30 minutes, one reviewed change)

1. Open a PR adding `gitops/tenants/<id>/values.yaml`. Copy `acme-eu`, then set `tenant.id`, `mode`, `residency`, `region` and `platform.ring`.
   - For a **dedicated cloud** tenant, the same PR also adds `infra/live/aws/<id>/`, a copy of `dedicated-acme-eu` with a new state key and region.
2. Review checks:
   - residency matches region (`eu` → `eu-*`); this is also enforced by Terraform validation and the onboarding script
   - sizing
   - ring
3. Merge.
   - **Cloud:** the pipeline applies `infra/live/aws/<id>` (production environment approval); Argo CD ApplicationSet creates the app.
   - **Local:** `scripts/onboard-tenant.sh <id>`.
4. Verify: the smoke test output (healthz/readyz/version), the tenant labels on pods, the NetworkPolicy isolation test (`scripts/test-isolation-residency.sh`).
5. **Timings:**
   - local Kubernetes layer: 16 s (measured)
   - cloud dedicated stack: about 20–25 min estimated (EKS + RDS Multi-AZ created in parallel), not measured
