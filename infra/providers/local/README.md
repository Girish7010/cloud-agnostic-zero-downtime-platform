# Local provider target

Use kind/k3d for Kubernetes portability tests. The local target does not emulate managed database, Redis, cloud IAM, cloud load balancers, KMS, or provider networking semantics. Run PostgreSQL/Redis only as disposable local dependencies; do not treat them as production HA.
