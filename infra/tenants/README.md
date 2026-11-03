# Tenant configuration

Use one reviewed configuration per tenant. Keep tenant data, secrets and state isolated. Never place credentials in tfvars committed to Git.

Example tenant metadata:
- tenant_id
- deployment_mode: shared | dedicated
- data_residency: eu | us
- region
- sizing_profile
- image_digest
