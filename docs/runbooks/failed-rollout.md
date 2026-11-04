# Runbook: failed rollout / fleet halt

**Signals:**
- `gated-rollout.sh` (or an Argo Rollouts AnalysisRun) reports `GATE 1 FAILED` or `GATE 2 FAILED`
- `fleet-rollout.sh` prints `HALTING FLEET ROLLOUT`
- alert `DeploymentReplicasUnavailable`

1. **Stop promotion.** Don't start further rings; the fleet script already stops. In GitOps, pause the ApplicationSet RollingSync or revert the digest PR.
2. **Confirm the automatic rollback happened.**
   - Run `helm history <release> -n <ns> | tail -3`. The last row should read `Rollback to N`.
   - Run `kubectl get deploy -n <ns> -o wide` and confirm the image digest is the previous one.
   - Tested locally: `evidence/submission-2026-11-04/rollback-bad-release-*`.
3. **Check the user impact window.** Look at k6 or production error rate between `Gate 1 passed` and `Rollback complete`. The local bad rolling release exposed 13% of requests for about 87 s; a canary reduces this.
4. **Find the cause.**
   - Gate 1 (pods never Ready): `kubectl describe pod`, `kubectl logs`, the readiness endpoint, config/secret differences.
   - Gate 2 (metrics): the 5xx breakdown by path from `/metrics`, plus app logs.
5. **Check the schema before any manual rollback.** If the failed release ran a migration, check whether it was additive (expand: rollback is safe) or destructive. If it was destructive, **do not** redeploy old code; follow `database-recovery.md`.
6. **Fix forward** with a new digest and rerun from ring 0. Never re-tag or mutate an existing digest.
7. **Record:** timeline, Helm history, gate output, affected tenants and error-budget impact.
