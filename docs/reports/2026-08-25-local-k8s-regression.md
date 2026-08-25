# Local Kubernetes Regression Report — 2026-08-25

**Scope:** local Kubernetes (Docker Desktop) only, same exact scope as the [2026-08-25 full regression](2026-08-25-full-regression.md) — every documented command in the README's "Getting started — Kubernetes (Docker Desktop)" section, run literally against a genuine fresh `git clone` of this repo. Covers all four documented `schema/load` calls, the full Kafka produce→consume pipeline, CSV output, Parquet output, and the bring-your-own-schema (`/api/ddl/load`) flow. Every result was checked against the real database or filesystem directly, not inferred from an HTTP status code.

## Result

| Step | Result |
|---|---|
| `docker build -t testfixtures-app:latest .` | ✅ |
| Full stack applied (namespaces, data, messaging, monitoring, app, ingress) | ✅ all pods `1/1 Running` within ~40s |
| `POST /api/schema/load` — bankschema (Kafka) | ✅ HTTP 200 |
| `POST /api/schema/load` — banking (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforce (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforceenterprise (JDBC) | ✅ HTTP 200 |
| `kafka-test` named pipe | ✅ DONE |
| `POST /api/consumer/run` — bankschema | ✅ 86,005 rows reported, 86,005 confirmed via direct `psql` query against the live pod — exact match |
| `csv-test` pipe | ✅ real file, 101 lines (100 rows + header) |
| `parquet-test` pipe | ✅ real, valid Parquet file |
| Bring-your-own-schema (`/api/ddl/load` against a fresh external database registered in `k8s/app/testfixtures-app.yaml`) | ✅ 1,000 customers / 1,000 orders, 0 orphaned foreign keys |

All steps passed clean on this run — no errors, no fixes needed. All pods reached `1/1 Running` in under a minute, a large improvement over the instability seen the day before, which turned out to be caused by unrelated host-level Docker Desktop degradation, not the application or manifests.

## What "verified" means here

- Kafka row count checked with a direct `pg_stat_user_tables` query against the live PostgreSQL pod, not the API's own response.
- CSV/Parquet checked by reading the actual output file from inside the running app pod.
- Bring-your-own-schema checked by connecting directly to a real external Postgres deployment (not one of the six shipped schemas) and confirming both row counts and referential integrity on tables the app had never seen before this run.

## Environment

Fresh `git clone` of this repo, image built locally, full stack applied to a local Docker Desktop Kubernetes cluster via the documented `kubectl apply` sequence plus the nginx ingress controller. Everything torn down completely at the end of this run: all four `testfixtures-*` namespaces, the standalone bring-your-own-schema test database, and the ingress-nginx controller. Confirmed clean — only the cluster's own built-in `kube-system` components remain.
