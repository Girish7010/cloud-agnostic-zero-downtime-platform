# Runbook: API errors or latency (SLOFastBurn / SLOSlowBurn / APILatencyP95High)

1. **Scope.** Which `tenant`? Shared or dedicated? A single tenant or all? Did it start after a deploy (`helm history`, Argo CD history)? If deploy-related, go to `failed-rollout.md`.
2. **Capacity.**
   - `kubectl get hpa -n <ns>`: at maxReplicas? `kubectl get pods`: any Pending (node capacity)?
   - If capped: raise `maxReplicas` or add nodes (cluster-autoscaler / overprovisioning).
3. **Dependencies.**
   - `/readyz` failing means Redis is unreachable; check the Valkey/Redis status and NetworkPolicy.
   - DB errors mean checking `PostgresConnectionsHigh`, RDS events and slow queries.
4. **Mitigate.**
   - Scale out.
   - Shed non-critical traffic at the LB.
   - Fail over the managed service if it's impaired (RDS reboot with failover / Valkey failover).
5. **Communicate.** Tenant status page; dedicated tenants within 15 minutes.
6. **Recover.** Confirm the SLIs are back under threshold for 30 minutes, then write the post-incident review.
