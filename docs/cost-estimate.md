# Monthly cost estimate (AWS, EU)

**Status: ESTIMATE, not a quote.** Prices are approximate on-demand list prices for eu-central-1 / eu-west-1 as I know them (USD, about 730 h/month). They have **not** been checked against the AWS Pricing Calculator for this submission. Do that before committing a budget. No resources were provisioned, so there is no billing data. Sizing follows `docs/architecture.md` §3 and `infra/live/aws/*/main.tf`.

## Assumptions
- **Fleet:** 1 shared production stack (EU), 3 dedicated EU tenant stacks, 1 staging, 1 dev.
- **Steady state:** 150 rps on the shared stack. Dedicated tenants are small (≤ 50 rps each).
- **Peak month:** the 15x peak (2,250 rps) is sustained long enough that peak capacity is billed for the whole month. This is a deliberately pessimistic reading of "USD 16,000 at peak".
- **Response size:** average 5 KB, so egress at 150 rps ≈ 1.9 TB/month and at 2,250 rps ≈ 29 TB/month.
- **Data services:** RDS and Valkey are Multi-AZ in production and dedicated stacks, single-AZ in staging and dev.
- **Rates used:**

| Item | Approx. rate |
|---|---|
| EKS control plane | $0.10/h |
| m6i.large | ~$0.115/h |
| m6i.xlarge | ~$0.23/h |
| db.r6g.large Multi-AZ | ~$0.58/h |
| cache.r7g.large | ~$0.25/h per node |
| cache.m7g.large | ~$0.20/h per node |
| NAT gateway | ~$0.052/h + $0.052/GB |
| Internet egress | ~$0.085/GB (after the first TB) |

- **Excluded:** support plan, Savings Plans/RI discounts (which would cut compute by 30–40%), WAF, third-party observability.

## Shared production stack (eu-central-1)
| Item | Steady | Peak month |
|---|---:|---:|
| EKS control plane | 73 | 73 |
| System nodes 2× m6i.large | 168 | 168 |
| App nodes m6i.xlarge (3 steady → 9 at peak: 28 vCPU of requests) | 504 | 1,512 |
| RDS PostgreSQL db.r6g.large Multi-AZ + 100 GB gp3 (peak: r6g.xlarge) | 450 | 900 |
| ElastiCache Valkey cache.r7g.large ×2 | 365 | 365 |
| NAT gateways ×3 + data processing | 175 | 350 |
| ALB (hours + LCU) | 60 | 150 |
| Internet egress | 165 | 2,450 |
| Logs, metrics, Prometheus storage | 300 | 600 |
| Backups/snapshots (14 d PITR, in-region) | 30 | 40 |
| **Subtotal** | **2,290** | **6,608** |

## Dedicated EU tenant stack (each; ×3)
| Item | Steady | Peak month |
|---|---:|---:|
| EKS control plane | 73 | 73 |
| Nodes 2× m6i.large system + 2× m6i.large app (peak +4 app) | 336 | 672 |
| RDS db.r6g.large Multi-AZ (99.95% SLO) | 450 | 450 |
| Valkey cache.m7g.large ×2 | 290 | 290 |
| NAT ×3, ALB, egress, logs | 350 | 700 |
| **Subtotal per tenant** | **1,499** | **2,185** |
| **×3 tenants** | **4,497** | **6,555** |

## Non-production and shared tooling
| Item | Steady | Peak month |
|---|---:|---:|
| Staging (single NAT, single-AZ RDS r6g.large, 1 Valkey node, 3 nodes) | 900 | 900 |
| Dev (smaller; scaled to zero nightly) | 450 | 450 |
| Registry (GHCR), CI minutes, state bucket, KMS keys, Secrets Manager | 100 | 100 |
| **Subtotal** | **1,450** | **1,450** |

## Total
| | Steady | Peak month | Budget | Headroom |
|---|---:|---:|---:|---:|
| **Total** | **≈ $8,240** | **≈ $14,610** | $9,000 / $16,000 | 8% / 9% |

## Sensitivities and levers
- **Egress dominates the peak.** At 10 KB responses, peak egress doubles to about $4.9k and breaks the budget. A CDN or compression for cacheable responses is the first lever.
- **Each extra dedicated tenant costs about $1.5k/month steady.** The steady budget therefore fits about 3 dedicated tenants. More than that needs a cheaper "dedicated" tier, which would mean single NAT, shared observability, and a dedicated node group plus a dedicated database in the shared cluster.
- **Commitments:** Compute Savings Plans (1 year) on the steady node baseline save about $500/month. Graviton (m7g) nodes save about another 15–20% once the black-box image is multi-arch.
- **Worker job duration** (see §3) is the biggest unknown. If the average job is 30 s rather than 10 s, worker vCPU roughly triples, adding about $1k at peak.
- **US dedicated stack** (change request, different cloud): about $2.0k/month extra (`docs/change-request-us.md`), which takes the steady total to about $10.2k. Over the $9k budget unless offset by the levers above or a tenant price uplift.
