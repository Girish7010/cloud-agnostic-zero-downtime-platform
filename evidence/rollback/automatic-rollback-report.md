# Automatic Rollback Test B: worker bad image tag (Helm revisions 15 → 17)

> **Label (added 2026-11-04):** the *later* of two separate tests (Test A = `automatic-rollback-test.md`, API, revisions 5→7). Helm rollback-on-failure only; not metric-gated, and no traffic measurement.

## Environment
- Platform: Local Kubernetes (kind)
- Namespace: devops-platform
- Deployment tool: Helm v4
- Application: Cloud Platform Reference Application

## Test
- Test type: Failed deployment with automatic rollback
- Helm option: --rollback-on-failure
- Target worker image tag: invalid-rollback-test
- Timeout: 60 seconds

## Result
- Upgrade revision: 16
- Upgrade status: Failed
- Failure reason: Worker deployment remained pending termination
  until the operation timed out.
- Rollback revision: 17
- Restored release revision: 15
- Rollback status: Successful

## Post-Rollback Verification
- Worker image: cloud-platform-reference:v3
- Worker deployment: Successfully rolled out
- Worker pod: 1/1 Running
- API deployment: 2/2 Running
- Redis deployment: 1/1 Running

## Conclusion
Helm automatically rolled back the failed upgrade.
The previous worker image and healthy deployment were restored.

## Limitations
This was a local kind-cluster test. It does not prove
production-cloud rollback behavior or database rollback safety.
