# Evidence register

- **Current submission evidence:** [`submission-2026-11-04/README.md`](submission-2026-11-04/README.md), including the index, raw logs, recordings and [limitations](submission-2026-11-04/limitations.md).
- **Earlier (3 Nov 2026, local kind):**
  - `rollout-availability-report.md` with raw log `raw/rollout-availability-20261103-185254.txt`: 60/60 periodic in-cluster health checks during a v1→v2 rolling upgrade.
  - `rollback/automatic-rollback-test.md`: **Test A**, an API with a bad tag; Helm revisions 5→7.
  - `rollback/automatic-rollback-report.md`: **Test B**, a worker with a bad tag; Helm revisions 15→17.
  - `raw/zero-downtime-traffic.txt`: **failed**, 50/120 via a host port-forward. Not used as zero-downtime evidence.
  - `raw/load-25rps.txt` and `raw/load-50rps.txt`: `/healthz` only, through a port-forward.
  - `worker-graceful-shutdown-report.md`: inconclusive. Superseded by `submission-2026-11-04/worker-drain/`.
  - `database-migration-report.md`: the expand/backfill/contract SQL demo.
- **Raw logs:** `raw/` holds byte-identical `.txt` copies of the original `*.log` files, which `.gitignore` excludes (see `raw/SHA256SUMS.txt`).

Never create synthetic logs or mark a test successful without running it.
