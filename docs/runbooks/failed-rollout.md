# Failed rollout
1. Stop promotion; do not continue tenant rings.
2. Inspect Argo Rollouts status/events and Prometheus gate metrics.
3. If the schema is compatible, abort and promote the last known-good image digest.
4. If a migration changed schema incompatibly, do not blindly redeploy old code; follow the migration recovery plan.
5. Capture rollout history, logs, metrics and incident timeline.
