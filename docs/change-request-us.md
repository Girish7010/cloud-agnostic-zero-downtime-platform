# Change request: second cloud, US-West primary / US-East failover

**Status: DESIGNED_NOT_IMPLEMENTED.** This is a post-24-hour change request, not part of the initial deployment evidence.

- Add a second provider implementation behind the same platform interfaces.
- Deploy a dedicated US tenant stack in a US-West region; establish a warm or pilot-light US-East recovery stack.
- Define database replication mode, RPO/RTO, Redis queue recovery semantics, object/backup replication, secrets/KMS, DNS failover and health checks.
- Test failover and failback, including duplicate-job/idempotency behavior.
- Estimate incremental provider, replication, data-transfer and standby costs.
- Keep EU tenant data isolated; do not replicate EU tenant data to US.
