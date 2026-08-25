# Azure AKS Regression Report — 2026-08-25

**Scope:** Azure AKS only, same exact scope as the [2026-08-25 full regression](2026-08-25-full-regression.md) — every documented command in the README's "Getting started — Azure (AKS)" section, run literally against a genuine fresh `git clone` of this repo. Covers `terraform apply`, image build/push, the full stack deploy, all four documented `schema/load` calls, the full Kafka produce→consume pipeline, CSV output, Parquet output, and the bring-your-own-schema (`/api/ddl/load`) flow, followed by `terraform destroy`. Every result was checked against the real database or filesystem directly, not inferred from an HTTP status code.

## Result

| Step | Result |
|---|---|
| `terraform apply` — 31 resources | ✅ |
| `./scripts/acr-build.sh` | ✅ |
| `./scripts/azure-deploy.sh` — full stack + schema bootstrap | ✅ clean on the first attempt, all pods `1/1 Running` |
| `POST /api/schema/load` — bankschema (Kafka) | ✅ HTTP 200 |
| `POST /api/schema/load` — banking (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforce (JDBC) | ✅ HTTP 200 |
| `POST /api/schema/load` — salesforceenterprise (JDBC) | ✅ HTTP 200 |
| `kafka-test` named pipe | ✅ DONE |
| `POST /api/consumer/run` — bankschema | ✅ 86,005 rows reported, 86,005 confirmed via exact `COUNT(*)` against the live managed Postgres — exact match |
| `csv-test` pipe | ✅ real file, 101 lines (100 rows + header) |
| `parquet-test` pipe | ✅ real, valid Parquet file |
| Bring-your-own-schema (`/api/ddl/load` against a fresh database on the same managed Postgres server) | ✅ 1,000 customers / 1,000 orders, 0 orphaned foreign keys |
| `terraform destroy` | ✅ all 31 resources removed, confirmed zero resource groups remaining |

All steps passed clean on this run — no errors, no fixes needed.

## What "verified" means here

- Kafka row count checked with a direct `COUNT(*)` query against the live managed PostgreSQL Flexible Server, not the API's own response, and not the `pg_stat_user_tables` estimate (which was observed to briefly lag reality on this platform in an earlier pass — a true `COUNT(*)` was used instead to avoid a false read).
- CSV/Parquet checked by reading the actual output file from inside the running app pod.
- Bring-your-own-schema checked by connecting directly to a second, independent database on the same managed server (not one of the six shipped schemas) and confirming both row counts and referential integrity on tables the app had never seen before this run.
- Environment teardown confirmed by listing resource groups after `terraform destroy` completed — zero remained.

## Region note

`eastus` — the default in `terraform.tfvars.example` — is currently subscription-restricted for PostgreSQL Flexible Server provisioning on this account (Azure-side capacity/policy restriction, not a code or configuration issue). `eastus2` was used instead for this run.

## Cost

One `terraform apply` → `terraform destroy` cycle: Standard_B2s AKS node, B1ms PostgreSQL Flexible Server, Basic ACR tier, running for roughly 20 minutes total. Well under $1 at current pricing.
