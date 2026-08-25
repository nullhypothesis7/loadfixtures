# Regression Summary — 2026-08-25

Follow-up to the [2026-08-25 full regression](2026-08-25-full-regression.md) run the day before, which found and fixed 8 issues across all three environments. Today's pass re-ran the exact same scope against each environment individually — Docker Compose, local Kubernetes, and Azure AKS — each from a genuine fresh `git clone`, each torn down completely afterward. The goal: confirm yesterday's fixes actually hold up on a clean run, not just in the moment they were fixed.

**Result: all three environments passed clean. Zero new issues, zero fixes needed.**

## Combined results

| | Docker Compose | Local K8s | Azure AKS |
|---|---|---|---|
| `schema/load` ×4 (JDBC + Kafka producer) | ✅ | ✅ | ✅ |
| Kafka produce → consume pipeline | ✅ 86,007 rows, exact DB match | ✅ 86,005 rows, exact DB match | ✅ 86,005 rows, exact DB match |
| CSV output | ✅ real file, 100 rows | ✅ real file, 100 rows | ✅ real file, 100 rows |
| Parquet output | ✅ valid file | ✅ valid file | ✅ valid file |
| Bring-your-own-schema | ✅ 1,000/1,000 rows, 0 orphaned FKs | ✅ 1,000/1,000 rows, 0 orphaned FKs | ✅ 1,000/1,000 rows, 0 orphaned FKs |
| Torn down after | ✅ `docker compose down -v` | ✅ all namespaces + ingress deleted | ✅ `terraform destroy`, 31/31 resources |

Every row count above was confirmed with a direct query against the live database, not read from the API's response.

## Individual reports

- [Docker Compose](2026-08-25-docker-compose-regression.md)
- [Local Kubernetes](2026-08-25-local-k8s-regression.md)
- [Azure AKS](2026-08-25-azure-regression.md)

## Notes

- Before the Docker Compose pass, yesterday's **local K8s** deployment was found still running (never torn down at the end of the previous session) — cleaned up before today's runs began.
- The Azure Postgres Flexible Server region (`eastus`, the documented default) remains subscription-restricted on this account, same as yesterday; `eastus2` was used instead. This is an Azure-side subscription restriction, not a code issue.
