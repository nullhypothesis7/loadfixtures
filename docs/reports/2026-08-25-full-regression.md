# Full Regression Report — 2026-08-25

**Scope:** every documented onboarding path in the README, run literally — copy-pasted commands, no shortcuts or custom scripts — against three environments: Docker Compose, local Kubernetes (Docker Desktop), and Azure AKS. Covers JDBC schema loads, the full Kafka produce→consume pipeline, CSV output, Parquet output, and the bring-your-own-schema (`/api/ddl/load`) flow. Every result below was checked against the real database or filesystem directly, not inferred from an HTTP status code.

## Result

| Environment | JDBC | Kafka (produce→consume) | CSV | Parquet | Bring-your-own-schema |
|---|---|---|---|---|---|
| Docker Compose | ✅ | ✅ (86,008 rows, exact DB match) | ✅ (101 lines, 100 rows) | ✅ (valid file) | ✅ (1,000/1,000 rows, 0 orphaned FKs) |
| Local K8s (Docker Desktop) | ✅ | ✅ (86,007 rows, exact DB match) | ✅ | ✅ | ✅ (1,000/1,000 rows, 0 orphaned FKs) |
| Azure AKS | ✅ | ✅ (89,008 rows, exact DB match) | ✅ | ✅ | ✅ (1,000/1,000 rows, 0 orphaned FKs) |

All three environments pass, verified end-to-end.

## What "verified" means here

- Kafka row counts checked with a direct `COUNT(*)`/`pg_stat_user_tables` query against the live database, not the API's own response — this specifically catches a class of bug where an app can report success while quietly dropping rows.
- CSV/Parquet checked by reading the actual output file from inside the running container/pod.
- Bring-your-own-schema checked by connecting to the target database directly and confirming both row counts and referential integrity (zero orphaned foreign keys) on tables the app had never seen before this run.

## Dashboards

Real Grafana screenshots, captured live during this pass.

### Pipeline Overview
![Pipeline Overview](../screenshots/pipeline-overview.png)

### App Metrics
![App Metrics](../screenshots/app-metrics.png)

### Database Metrics
![Database Metrics](../screenshots/database-metrics.png)

### Kafka Metrics
![Kafka Metrics](../screenshots/kafka-metrics.png)

Side-by-side local vs. Azure captures from an earlier parallel run are also in [`docs/screenshots/2026-08-21-parallel-k8s/`](../screenshots/2026-08-21-parallel-k8s/).

## Issues found and fixed during this pass

Running every documented path literally — rather than the shorter path a maintainer already familiar with the tool might take — surfaced eight real issues. None of these were previously caught because nothing had exercised these exact code paths end-to-end before.

| # | Issue | Root cause | Fix |
|---|---|---|---|
| 1 | `POST /api/ddl/load` silently failed to insert any data | Endpoint parsed the DDL for type inference but never executed the `CREATE TABLE` statements against the target database | Endpoint now executes the DDL before enqueueing generation, treating "table already exists" as a no-op |
| 2 | Kafka row counts didn't match what was actually written | `ON CONFLICT DO NOTHING` silently swallowed some inserts, but the reported count assumed every row succeeded | Sinks now report the real `executeBatch()` result, not `rows.size()` |
| 3–5 | Re-running the Azure deploy script against an already-seeded database aborted with "relation already exists" | Three of the shipped schema SQL files (the two Salesforce schemas and the 88-table bank schema) had no `DROP TABLE IF EXISTS` guards, unlike the smaller schema files | Added `DROP TABLE IF EXISTS ... CASCADE` for every table across all three files |
| 6 | K8s pods (Postgres, Kafka exporters, schema registry) intermittently crash-looped under real concurrent load | Per-container CPU *limits* were tight enough that the kernel throttled a container even while the node had many idle cores free — a different failure mode than insufficient probe timeouts | Raised CPU limits on the affected containers |
| 7 | `git clone`/CI badge/API examples in the README 404'd | Broken repo-name references | Corrected |
| 8 | `terraform apply` failed immediately on a fresh checkout | `terraform.tfvars.example` was missing the required `subscription_id` field the README instructs you to set | Added the missing field |

Every fix was verified by re-running the specific path that had failed, then by re-running the complete regression from a fresh clone.

## Azure cost

Two full `terraform apply` → `terraform destroy` cycles during this pass (one hit a regional capacity restriction and was redone in a different region). Estimated total: well under $1 at current pricing — Standard_B2s AKS node, B1ms PostgreSQL Flexible Server, Basic ACR tier, each running for under an hour. Environment fully torn down and confirmed clean (zero resource groups remaining) at the end of this pass.
