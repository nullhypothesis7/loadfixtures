#!/usr/bin/env bash
# Deploy the full testfixtures stack to AKS after `terraform apply`.
# Applies every manifest in k8s/azure/ in dependency order.
#
# Usage:
#   ./scripts/azure-deploy.sh [IMAGE_TAG]
#
# IMAGE_TAG defaults to "latest". Use a git SHA or the same tag passed to
# acr-build.sh for a reproducible deployment.
#
# Prerequisites:
#   - terraform apply completed in terraform/
#   - az CLI authenticated (az login)
#   - kubectl installed
#   - envsubst installed (brew install gettext on macOS)
#   - Image already pushed to ACR (run acr-build.sh first)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
K8S="${REPO_ROOT}/k8s/azure"
IMAGE_TAG="latest"
LIFECYCLE="manual"

# ── Argument parsing ──────────────────────────────────────────────────────────
# Usage: azure-deploy.sh [--auto] [IMAGE_TAG]
#   --auto     tag the environment to destroy when tests signal completion
#   IMAGE_TAG  defaults to "latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto)
      LIFECYCLE="auto"
      shift
      ;;
    *)
      IMAGE_TAG="$1"
      shift
      ;;
  esac
done

# ── Preflight ─────────────────────────────────────────────────────────────────
# Validates and auto-fixes prerequisites (az login, Docker, tfvars, kubectl
# context, ACR image). Exits with an error if anything requires human action.

bash "${REPO_ROOT}/scripts/preflight.sh"

# ── Read terraform outputs ────────────────────────────────────────────────────

echo "==> Reading terraform outputs..."
cd "${TF_DIR}"

export ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server)
export AKS_CLUSTER_NAME=$(terraform output -raw aks_cluster_name)
export RESOURCE_GROUP=$(terraform output -raw resource_group_name)
export KEY_VAULT_NAME=$(terraform output -raw key_vault_name)
export POSTGRES_FQDN=$(terraform output -raw postgres_fqdn)
export APP_NAMESPACE=$(terraform output -raw app_namespace)
export APP_SERVICE_ACCOUNT=$(terraform output -raw app_service_account)
export WORKLOAD_IDENTITY_CLIENT_ID=$(terraform output -raw workload_identity_client_id)
export TENANT_ID=$(az account show --query tenantId -o tsv)

# Non-sensitive config — override via env if pointing at external services
export PG_ADMIN_USERNAME="${PG_ADMIN_USERNAME:-pgadmin}"
export REDIS_HOST="${REDIS_HOST:-redis.testfixtures-data.svc.cluster.local}"
export KAFKA_BROKERS="${KAFKA_BROKERS:-kafka.testfixtures-messaging.svc.cluster.local:9092}"
export APP_IMAGE_TAG="${IMAGE_TAG}"

printf "  AKS    : %s\n  ACR    : %s\n  NS     : %s\n  PGFQDN : %s\n  Tag    : %s\n\n" \
  "${AKS_CLUSTER_NAME}" "${ACR_LOGIN_SERVER}" "${APP_NAMESPACE}" "${POSTGRES_FQDN}" "${IMAGE_TAG}"

# ── Configure kubectl ─────────────────────────────────────────────────────────

echo "==> Fetching AKS credentials..."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AKS_CLUSTER_NAME}" \
  --overwrite-existing

# ── 1. Namespaces (must exist before any other resource) ─────────────────────

echo "==> Applying namespaces..."
kubectl apply -f "${K8S}/namespaces.yaml"

echo "==> Applying workload identity service account..."
envsubst < "${K8S}/service-account.yaml" | kubectl apply -f -

# ── 1.5 Bootstrap Postgres schema ─────────────────────────────────────────────
# Azure Database for PostgreSQL Flexible Server is a managed PaaS instance —
# there's no docker-entrypoint-initdb.d equivalent, so nothing else creates
# the tables the shipped pipes write into. Apply the same DDL files Docker
# Compose / Docker Desktop K8s use, via a one-off Job (this script's host has
# no route to the private VNet; the cluster does).

echo "==> Bootstrapping Postgres schema (testdb, bankingdb, healthcaredb, pgbank, salesforcedb, salesforceenterprisedb)..."

echo "==> Fetching pg-admin-password from Key Vault..."
PG_ADMIN_PASSWORD=$(az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "pg-admin-password" \
  --query value -o tsv)

kubectl create secret generic pg-schema-init-creds \
  --namespace testfixtures-data \
  --from-literal=PGPASSWORD="${PG_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
unset PG_ADMIN_PASSWORD

kubectl create configmap pg-schema-init \
  --namespace testfixtures-data \
  --from-file="${REPO_ROOT}/src/main/resources/sql/smoke_test.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/example_table.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/banking_schema.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/healthcare_schema.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/bank_schema.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/salesforce_schema.sql" \
  --from-file="${REPO_ROOT}/src/main/resources/sql/salesforce_enterprise_schema.sql" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job pg-schema-init --namespace testfixtures-data --ignore-not-found

cat <<JOBEOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: pg-schema-init
  namespace: testfixtures-data
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: psql
          image: postgres:16
          env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: pg-schema-init-creds
                  key: PGPASSWORD
          command:
            - /bin/bash
            - -c
            - |
              set -euo pipefail
              run() {
                echo "==> Applying \$1 to database \$2..."
                psql "host=${POSTGRES_FQDN} port=5432 dbname=\$2 user=${PG_ADMIN_USERNAME} sslmode=require" \
                  -v ON_ERROR_STOP=1 -f "/sql/\$1"
              }
              run smoke_test.sql testdb
              run example_table.sql testdb
              run banking_schema.sql bankingdb
              run healthcare_schema.sql healthcaredb
              run bank_schema.sql pgbank
              run salesforce_schema.sql salesforcedb
              run salesforce_enterprise_schema.sql salesforceenterprisedb
              echo "Schema bootstrap complete."
          volumeMounts:
            - name: sql
              mountPath: /sql
      volumes:
        - name: sql
          configMap:
            name: pg-schema-init
JOBEOF

echo "==> Waiting for schema bootstrap job (up to 180s)..."
kubectl wait --namespace testfixtures-data --for=condition=complete job/pg-schema-init --timeout=180s \
  || { kubectl logs --namespace testfixtures-data job/pg-schema-init; exit 1; }
kubectl logs --namespace testfixtures-data job/pg-schema-init

kubectl delete job pg-schema-init --namespace testfixtures-data --ignore-not-found
kubectl delete configmap pg-schema-init --namespace testfixtures-data --ignore-not-found
kubectl delete secret pg-schema-init-creds --namespace testfixtures-data --ignore-not-found

# ── 2. Stateful services (Redis, Kafka, Schema Registry, Kafka UI) ────────────
# These have long startup times; apply early so they're ready by the time the
# app and monitoring reach their readiness probes.

echo "==> Applying Redis..."
kubectl apply -f "${K8S}/redis.yaml"

echo "==> Applying Kafka, Schema Registry, Kafka exporters, Kafka UI..."
kubectl apply -f "${K8S}/kafka.yaml"

# ── 3. App: SecretProviderClass then Deployment ───────────────────────────────
# SecretProviderClass must exist before the pod that references it is scheduled.

echo "==> Applying SecretProviderClass..."
envsubst < "${K8S}/secret-provider-class.yaml" | kubectl apply -f -

echo "==> Applying app Deployment..."
envsubst < "${K8S}/deployment.yaml" | kubectl apply -f -

# ── 4. Monitoring ─────────────────────────────────────────────────────────────
# Fetch the pg admin password from Key Vault and create a K8s Secret in the
# monitoring namespace so the PG exporters can authenticate. The password never
# touches disk or this script's stdout.

echo "==> Fetching pg-admin-password from Key Vault..."
PG_ADMIN_PASSWORD=$(az keyvault secret show \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "pg-admin-password" \
  --query value -o tsv)

echo "==> Creating pg-exporter-credentials secret in testfixtures-monitoring..."
kubectl create secret generic pg-exporter-credentials \
  --namespace testfixtures-monitoring \
  --from-literal=PG_ADMIN_PASSWORD="${PG_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

unset PG_ADMIN_PASSWORD

echo "==> Applying Prometheus and PG exporters..."
envsubst < "${K8S}/monitoring.yaml" | kubectl apply -f -

echo "==> Applying Grafana..."
kubectl apply -f "${K8S}/grafana.yaml"

# ── 5. Wait for rollouts ──────────────────────────────────────────────────────

echo ""
echo "==> Waiting for app rollout (180s)..."
kubectl rollout status deployment/testfixtures-app \
  --namespace "${APP_NAMESPACE}" --timeout=180s

echo "==> Waiting for Prometheus rollout..."
kubectl rollout status deployment/prometheus \
  --namespace testfixtures-monitoring --timeout=120s

echo "==> Waiting for Grafana rollout..."
# 300s, not 120s: the grafana-image-renderer sidecar is an extra image pull
# on top of Grafana's own, and on a node that's never cached it before that
# alone can take 2+ minutes — 120s was cutting it close enough to fail here.
kubectl rollout status deployment/grafana \
  --namespace testfixtures-monitoring --timeout=300s

# ── 6. nginx Ingress controller + Ingress resources ──────────────────────────

echo ""
echo "==> Installing nginx ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

echo "==> Waiting for ingress controller pod..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "==> Waiting for ingress controller LoadBalancer IP (up to 3 min)..."
INGRESS_IP=""
for i in $(seq 1 36); do
  INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
    --namespace ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$INGRESS_IP" ]] && break
  sleep 5
done

if [[ -z "$INGRESS_IP" ]]; then
  echo "  WARNING: Could not obtain ingress IP — skipping Ingress resources."
  echo "  Run 'kubectl get svc -n ingress-nginx' when the IP is assigned, then:"
  echo "  INGRESS_IP=<ip> APP_NAMESPACE=${APP_NAMESPACE} envsubst < k8s/azure/ingress.yaml | kubectl apply -f -"
else
  export INGRESS_IP
  echo "  Ingress IP: ${INGRESS_IP}"
  echo "==> Applying Ingress resources..."
  envsubst < "${K8S}/ingress.yaml" | kubectl apply -f -
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────

echo ""
echo "==> Deployment complete. Pod status:"
kubectl get pods -A -l app.kubernetes.io/part-of=testfixtures 2>/dev/null || \
  kubectl get pods --namespace "${APP_NAMESPACE}" && \
  kubectl get pods --namespace testfixtures-data && \
  kubectl get pods --namespace testfixtures-messaging && \
  kubectl get pods --namespace testfixtures-monitoring

echo ""
echo "==> Tagging environment lifecycle (lifecycle=${LIFECYCLE})..."
if [[ "$LIFECYCLE" == "auto" ]]; then
  az group update --name "${RESOURCE_GROUP}" \
    --tags lifecycle=auto > /dev/null
  echo "  Environment will be destroyed when tests signal completion."
else
  az group update --name "${RESOURCE_GROUP}" \
    --tags lifecycle=manual > /dev/null
  echo "  No auto-destroy configured. Run the destroy workflow manually when done."
fi

echo ""
if [[ -n "${INGRESS_IP:-}" ]]; then
  echo "==> Service URLs (no port-forward required):"
  echo "  App API  : http://app.${INGRESS_IP}.nip.io"
  echo "  Grafana  : http://grafana.${INGRESS_IP}.nip.io"
  echo "  Prometheus: http://prometheus.${INGRESS_IP}.nip.io"
  echo "  Kafka UI : http://kafka-ui.${INGRESS_IP}.nip.io"
else
  echo "==> Port-forward fallback (ingress IP not available):"
  echo "  kubectl port-forward svc/testfixtures-app 8080:8080 -n ${APP_NAMESPACE}"
  echo "  kubectl port-forward svc/grafana 3000:3000 -n testfixtures-monitoring"
  echo "  kubectl port-forward svc/prometheus 9090:9090 -n testfixtures-monitoring"
  echo "  kubectl port-forward svc/kafka-ui 8081:8080 -n testfixtures-messaging"
fi
