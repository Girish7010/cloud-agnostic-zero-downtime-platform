# Pipelines

The canonical pipeline lives in `.github/workflows/` (GitHub only discovers workflows there):

| File | Purpose |
|---|---|
| `ci.yml` | verify → build once → Trivy scan → CycloneDX SBOM → Cosign keyless sign + SBOM attestation → promote dev → staging → production |
| `promote.yml` | reusable promotion: verify signature/attestation of the digest, move env tag to the **same** digest |
| `drift-detection.yml` | nightly `terraform plan -detailed-exitcode` via OIDC (skipped until AWS variables exist) |

`pipelines/github-actions/ci.yml` (an earlier scaffold) was removed on 2026-11-04 after its only unique
content — the `packages: write` / `id-token: write` permissions — was merged into `ci.yml`. It remains in Git history.
