# Docker Compose Regression Report — 2026-08-25

**Scope:** Docker Compose only, same exact scope as the [2026-08-25 full regression](2026-08-25-full-regression.md) — every documented command in the README's "Getting started — Docker Compose" section, run literally against a genuine fresh `git clone` of this repo. Covers all four documented `schema/load` calls, the full Kafka produce→consume pipeline, CSV output, Parquet output, and the bring-your-own-schema (`/api/ddl/load`) flow. Every result was checked against the real database or filesystem directly, not inferred from an HTTP status code.

## Result

| Step | Result |
|---|---|
| `docker compose up -d` — all services healthy | ✅ |
| `POST /api/schema/load` — bankschema (Kafka) | ✅ HTTP 200 |
| `POST /api/schema/load` — banking (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforce (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforceenterprise (JDBC) | ✅ HTTP 200 |
| `kafka-test` named pipe | ✅ DONE |
| `POST /api/consumer/run` — bankschema | ✅ 86,007 rows reported, 86,007 confirmed via direct `psql` query — exact match |
| `csv-test` pipe | ✅ real file, 101 lines (100 rows + header) |
| `parquet-test` pipe | ✅ real, valid Parquet file |
| Bring-your-own-schema (`/api/ddl/load` against a fresh external database) | ✅ 1,000 customers / 1,000 orders, 0 orphaned foreign keys |

All steps passed clean on this run — no errors, no fixes needed.

## What "verified" means here

- Kafka row count checked with a direct `pg_stat_user_tables` query against the live database, not the API's own response.
- CSV/Parquet checked by reading the actual output file from inside the running container.
- Bring-your-own-schema checked by connecting directly to a real external Postgres database (not one of the six shipped schemas) and confirming both row counts and referential integrity on tables the app had never seen before this run.

## Environment

Fresh `git clone` of this repo, `docker compose up -d`, torn down completely (`docker compose down -v` + removal of the standalone bring-your-own-schema test database) at the end of this run. No containers or volumes left behind.
