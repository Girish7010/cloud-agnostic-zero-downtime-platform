# Local provider target (kind)

Second target for the same platform: a kind cluster created by Terraform
(`tehcyx/kind` provider) that exposes the **same output contract** as
`modules/aws-stack` (see `../../README.md`).

```bash
terraform -chdir=infra/providers/local init
terraform -chdir=infra/providers/local apply        # creates kind cluster "devops-assignment"
terraform -chdir=infra/providers/local output        # contract values
```

Then run `infra/platform` with `target = "local"` and
`kubeconfig_path = $(terraform -chdir=infra/providers/local output -raw kubeconfig_path)`.

Use kind for Kubernetes portability tests. The local target does **not**
emulate managed database, Redis, cloud IAM, cloud load balancers, KMS, node
autoscaling or provider networking semantics. PostgreSQL/Redis run only as
disposable in-cluster dependencies:

| Contract output | Local value |
|---|---|
| `postgres_host` | `migration-postgres.devops-platform.svc` (from `database/postgres-test.yaml`) |
| `redis_host` | `devops-platform-redis.devops-platform.svc` (from `deploy/chart/templates/redis.yaml`) |
| `secret_store` | `kubernetes` |

Do not treat them as production HA. State is local (disposable cluster) and
contains the cluster client key; it is gitignored.
