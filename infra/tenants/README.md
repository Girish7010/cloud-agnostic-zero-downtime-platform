# Tenant configuration

Use one reviewed configuration per tenant. Keep tenant data, secrets and state
isolated. Never place credentials in tfvars committed to Git (none are needed:
database and Redis credentials are generated into Secrets Manager).

## Tenant stack = module instance + GitOps values

| Mode | Infrastructure (Terraform) | Application (GitOps) |
|---|---|---|
| `shared` | none new: runs on `infra/live/aws/shared-eu` | tenant values file in the shared Argo CD app |
| `dedicated` | own directory `infra/live/aws/dedicated-<tenant>-<residency>/` = one `modules/aws-stack` instance with its own state key, VPC, EKS, RDS, Valkey, KMS key | Argo CD Application targeting the tenant's cluster |

Adding a dedicated tenant is one reviewed pull request:

1. `cp -r infra/live/aws/dedicated-acme-eu infra/live/aws/dedicated-<tenant>-eu`
2. Edit the `locals` block in `main.tf` (tenant_id, region, vpc_cidr, sizing)
   and the state `key` in `versions.tf`.
3. Add the tenant's GitOps values (image digest, replica bounds, secret refs
   from the stack outputs).
4. CI plans with the read-only role; after approval the `production`
   environment applies with the apply role.

`data_residency = "eu"` with a non `eu-*` region fails `terraform plan`.

## Tenant metadata

- `tenant_id`
- `deployment_mode`: shared | dedicated
- `data_residency`: eu | us
- `region`
- sizing profile (node min/max, DB and cache instance classes)
- `image_digest` (GitOps values, not Terraform)
