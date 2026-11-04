# Archive: obsolete material (not the current design)

| File | What it is |
|---|---|
| `Pasted image.png` | **Obsolete architecture draft from an earlier project idea. It is NOT this platform's design.** It shows a single us-east-1 EKS cluster, a "Healthcare API", a DynamoDB lock table, an in-cluster PostgreSQL StatefulSet and HTTP on port 80. All of these contradict the current design: EU region with EU residency guards, S3 native state locking, RDS PostgreSQL, and Valkey. Kept only for history. |

The current architecture is [`../architecture.md`](../architecture.md) (PDF: [`../pdf/architecture.pdf`](../pdf/architecture.pdf)).
