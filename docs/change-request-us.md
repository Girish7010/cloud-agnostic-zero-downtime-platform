# CR-001: Dedicated US stack on a second cloud (US-West primary, US-East failover)

**Status: DESIGN — not provisioned or tested.** Received after the 24-hour mark.

**Scope.** One dedicated US tenant on **Google Cloud** (a different provider from AWS):
- primary in **us-west1**, warm standby in **us-east4**
- US-resident data; EU tenant data is never replicated to it

**Design: same platform, new provider module.**
- **Provider layer:** add `infra/modules/gcp-stack`, exporting the existing output contract (`cluster_endpoint`, `postgres_*`, `redis_*`, `secret_store`, `region`, `data_residency=us`). The residency validation allows `us-*` regions only.
- **Service mapping:**

| AWS | GCP |
|---|---|
| EKS | GKE regional (private) |
| RDS | Cloud SQL PostgreSQL HA + cross-region replica |
| ElastiCache | Memorystore Redis Standard |
| Secrets Manager | Secret Manager + ESO |
| KMS | Cloud KMS |
| IRSA | Workload Identity |
| ALB / Route 53 | Global HTTPS LB / Cloud DNS |

- **CI:** GitHub OIDC into GCP Workload Identity Federation (no keys).
- **Platform and app layers:** unchanged, with the same chart and the **same signed digest** from GHCR.
- **Fleet:** added as **ring 3**, promoted last.

**Replication, RPO and RTO.**

| Component | Mode | RPO | RTO |
|---|---|---|---|
| PostgreSQL | Cloud SQL HA (zonal) + **async** cross-region replica | ≤ 1 min (alert if lag > 30 s) | ≤ 15 min (promote replica) |
| Redis queue | **Not replicated.** Standby instance pre-created; API writes job intents to PostgreSQL (**outbox**, an app change) for re-enqueue | 0 with outbox (else in-flight jobs lost) | ≤ 15 min |
| GKE workloads | Standby at minimum size, synced by Argo CD from the same Git/digest | n/a (stateless) | ≤ 10 min scale-up |
| Backups | PITR 7 d + daily export to a US-only bucket | ≤ 5 min | 1–2 h |

**Tenant target: RPO ≤ 1 min, RTO ≤ 30 min.** A regional failover exceeds the 21.9-minute monthly budget of 99.95%; that is accepted for region loss only.

**Failover.**
- **Trigger:** all three conditions for 5 minutes: external probes from 3 locations failing, burn-rate page firing, provider regional incident.
- **Decision:** a human approves, because database split-brain is worse than a few minutes' delay.
- **Steps:** (1) freeze deploys; (2) promote the replica; (3) repoint secrets; (4) scale us-east4; (5) re-enqueue the outbox; (6) switch LB/DNS (TTL 60 s); (7) verify SLIs.
- **Failback:** rebuild a replica in us-west1, wait for lag under 5 s, switch over in a maintenance window. At-least-once delivery plus idempotency markers make re-enqueued jobs safe.

**Network, security, observability.**
- **Network:** private GKE per region, Private Service Connect to the data services, HA VPN for replication only, **no path to EU stacks**, Cloud Armor.
- **Isolation:** separate GCP project and US state bucket.
- **Observability:** same alert rules and `tenant` labels, with US telemetry kept in the US. New alerts: replica lag, standby readiness and outbox depth.

**Cost (GCP list prices, approximate, unverified):** primary ≈ $1,360/month (GKE, 3× n2-standard-4, Cloud SQL HA 4 vCPU/16 GB, Memorystore 5 GB, LB/NAT/logs) + warm standby ≈ $680 + replication egress ≈ $50 = **≈ $2.1k/month**. That takes the fleet to ≈ $10.3k steady, **over the $9k budget** unless offset (Savings Plans, Graviton, CDN) or charged to the tenant.

**Plan (about 2 weeks):** (1) GCP project, state bucket and WIF; (2) `gcp-stack` module and `live/gcp/dedicated-us`; (3) API outbox; (4) platform layer with `target=gcp`; (5) Argo CD registration and ring 3; (6) failover/failback game day with measured RPO/RTO; (7) residency audit.

**Risks:** queue loss without the outbox; provider differences in Postgres failover; budget.
