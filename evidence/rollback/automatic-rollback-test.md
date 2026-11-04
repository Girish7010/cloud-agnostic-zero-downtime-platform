# Automatic Rollback Test A: API bad image tag (Helm revisions 5 → 7)

> **Label (added 2026-11-04):** this is the *earlier* of two separate Helm rollback tests. Test B (worker, revisions 15→17) is `automatic-rollback-report.md`. This was Helm rollback-on-failure, **not** a metric-gated rollback. The "continuous health-check output" it mentions was captured through a host port-forward and showed **50/120 failures** (`../raw/zero-downtime-traffic.txt`), so it is not zero-downtime evidence. Metric-gated rollback was tested on 2026-11-04 (`../submission-2026-11-04/rollback-bad-release-*`).

Date: 2026-11-03
Environment: Local Kubernetes (kind)
Release: devops-platform
Namespace: devops-platform

## Test objective
Verify automatic rollback when a new API deployment fails.

## Test procedure
1. Confirmed API v2 was healthy.
2. Started continuous HTTP health checks.
3. Attempted deployment with invalid image tag:
   does-not-exist
4. Helm detected deployment timeout.
5. Helm automatically rolled back to the previous successful release.

## Results
- Invalid deployment: Failed as expected
- Automatic rollback: Successful
- Final Helm revision: 7
- API image: cloud-platform-reference:v2
- API replicas: 2/2 Ready
- /version: v2
- /healthz: HTTP 200
- /readyz: HTTP 200
- Redis: Connected

## Conclusion
Automatic rollback was verified successfully.
The previous healthy API version was restored.

Note: Continuous health-check output should be retained separately
to document request availability during the rollout.
