# Worker Graceful Shutdown Test

## Environment
- Platform: Local Kubernetes (kind)
- Namespace: devops-platform
- Queue: Redis Streams
- Worker image: cloud-platform-reference:v3
- Worker replicas: 1

## Test
- Job ID: graceful-shutdown-v3-test
- Job duration: 45 seconds
- Job submission: Accepted
- Worker processing: Confirmed in logs
- Worker pod: Deleted during the test
- Replacement worker: Running successfully

## Redis verification
- Consumer group: job-workers
- Pending messages after restart: 0
- Queue lag: 0

## Limitations
The old worker's shutdown and completion logs were not
captured. Therefore, successful completion during shutdown
was not conclusively demonstrated.

The test confirms worker replacement and an empty pending
queue after the restart, but does not prove exactly-once
job execution or production-grade job recovery.

> **Superseded (2026-11-04):** a repeatable test that captures the old worker's logs, job ID and XACK passed: `submission-2026-11-04/worker-drain/`.
