#!/usr/bin/env bash
# scripts/preflight.sh — validate and auto-fix Azure deployment prerequisites.
#
# Called automatically by azure-deploy.sh. Safe to run standalone.
#
# What it fixes without prompting:
#   - Stale/missing az login     → initiates az login (browser or device code)
#   - Wrong active subscription  → az account set
#   - Docker Desktop not running → opens app and waits (macOS only)
#   - kubectl pointing at wrong  → az aks get-credentials --overwrite-existing
#     or missing AKS context
#   - ACR image missing for HEAD → runs acr-build.sh
#   - Optional KV secrets absent → creates redis-password / kafka-username /
#     (redis / kafka)              kafka-password as empty strings
#
# What it refuses to fix (requires human intervention):
#   - terraform.tfvars missing or placeholder password still set
#   - required field (subscription_id, pg_admin_password) missing from tfvars
#   - Docker won't start after 60 s on macOS; Docker not running on non-macOS
#   - az login fails (wrong credentials, MFA timeout, etc.)
#   - tool not installed: az, terraform, docker, kubectl, envsubst, git

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${REPO_ROOT}/terraform"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
TF_VARS="${TF_DIR}/terraform.tfvars"

# ── Output helpers ────────────────────────────────────────────────────────────

fix()   { echo "[preflight] fix: $*"; }
fatal() { echo "[preflight] error: $*" >&2; exit 1; }

# ── Required tool check ───────────────────────────────────────────────────────

for tool in az terraform docker kubectl envsubst git; do
  command -v "${tool}" >/dev/null 2>&1 \
    || fatal "'${tool}' not found in PATH. Install it and re-run."
done

# ── Helpers ───────────────────────────────────────────────────────────────────

# Extract a value from terraform.tfvars — strips surrounding quotes/spaces.
tfvar() {
  grep -E "^[[:space:]]*${1}[[:space:]]*=" "${TF_VARS}" 2>/dev/null \
    | head -1 \
    | sed 's/^[^=]*=[[:space:]]*//' \
    | tr -d '"'"'"' '
}

# Read a terraform output; returns empty string on any error.
tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

# ── 1. terraform.tfvars ───────────────────────────────────────────────────────
# Check before az login so the user gets a clear message about config problems
# rather than a confusing authentication error.

[[ -f "${TF_VARS}" ]] \
  || fatal "terraform/terraform.tfvars not found. Copy terraform/terraform.tfvars.example, fill in all values, and re-run."

for field in subscription_id pg_admin_password; do
  val="$(tfvar "${field}")"
  [[ -n "${val}" ]] \
    || fatal "terraform.tfvars: '${field}' is missing or empty."
done

PG_PASS="$(tfvar pg_admin_password)"
[[ "${PG_PASS}" != "CHANGE_ME_strong_password_1!" ]] \
  || fatal "terraform.tfvars: pg_admin_password is still the example placeholder. Set a real password."

SUB_ID="$(tfvar subscription_id)"

# ── 2. Azure CLI login ────────────────────────────────────────────────────────

if ! az account show --query id -o tsv >/dev/null 2>&1; then
  fix "not logged in to Azure CLI — initiating az login..."
  az login --output none
  az account show --query id -o tsv >/dev/null 2>&1 \
    || fatal "az login did not complete. Run 'az login' manually and re-run this script."
fi

# Ensure the subscription from tfvars is active.
CURRENT_SUB="$(az account show --query id -o tsv 2>/dev/null || true)"
if [[ "${CURRENT_SUB}" != "${SUB_ID}" ]]; then
  fix "switching active subscription to ${SUB_ID}"
  az account set --subscription "${SUB_ID}"
fi

# ── 3. Docker Desktop ─────────────────────────────────────────────────────────

if ! docker info >/dev/null 2>&1; then
  if [[ "$(uname)" == "Darwin" ]]; then
    fix "Docker Desktop is not running — starting it (waiting up to 60 s)..."
    open -a Docker 2>/dev/null \
      || fatal "Could not launch Docker Desktop. Start it manually and re-run."
    for i in $(seq 1 30); do
      sleep 2
      if docker info >/dev/null 2>&1; then break; fi
      if [[ ${i} -eq 30 ]]; then
        fatal "Docker Desktop did not become ready after 60 s. Start it manually and re-run."
      fi
    done
  else
    fatal "Docker is not running. Start the Docker daemon and re-run this script."
  fi
fi

# ── 4. Terraform-state-dependent checks ──────────────────────────────────────
# terraform output retains the last-applied values even after destroy.
# Read the output first, then verify the resource actually exists in Azure
# before proceeding — this prevents trying to use destroyed infrastructure.

KV_NAME="$(tf_output key_vault_name)"

if [[ -z "${KV_NAME}" ]]; then
  echo "[preflight] done (terraform not yet applied — infra checks skipped)."
  exit 0
fi

if ! az keyvault show --name "${KV_NAME}" --query id -o tsv >/dev/null 2>&1; then
  echo "[preflight] done (infrastructure not found in Azure — run terraform apply first)."
  exit 0
fi

ACR_NAME="$(tf_output acr_name)"
AKS_NAME="$(tf_output aks_cluster_name)"
RG_NAME="$(tf_output resource_group_name)"

# ── 4a. Optional Key Vault secrets (redis / kafka) ────────────────────────────
# Terraform skips these secrets when the corresponding tfvars field is empty
# (count = 0).  Create them as empty-string secrets so they exist in Key Vault
# for any future SecretProviderClass entry or direct KV consumer.
#
# Azure CLI does not accept --value "" (treats empty string as unset), so we
# write an empty temp file and use --file instead.

_EMPTY="$(mktemp)"
trap 'rm -f "${_EMPTY}"' EXIT
: > "${_EMPTY}"   # guaranteed empty

for secret_name in redis-password kafka-username kafka-password; do
  case "${secret_name}" in
    redis-password) tf_key="redis_password" ;;
    kafka-username) tf_key="kafka_username" ;;
    kafka-password) tf_key="kafka_password" ;;
  esac

  tfval="$(tfvar "${tf_key}")"

  # Only create the placeholder when the field is empty in tfvars.
  # If a real value is set, terraform manages the secret; leave it alone.
  if [[ -z "${tfval}" ]]; then
    if ! az keyvault secret show \
        --vault-name "${KV_NAME}" \
        --name "${secret_name}" \
        --query id -o tsv >/dev/null 2>&1; then
      fix "creating Key Vault secret '${secret_name}' = '' (not configured in tfvars)"
      az keyvault secret set \
        --vault-name "${KV_NAME}" \
        --name "${secret_name}" \
        --file "${_EMPTY}" \
        --output none
    fi
  fi
done

# ── 4b. kubectl context ───────────────────────────────────────────────────────

CURRENT_CTX="$(kubectl config current-context 2>/dev/null || true)"
if [[ "${CURRENT_CTX}" != "${AKS_NAME}" ]]; then
  fix "kubectl context is '${CURRENT_CTX:-<none>}' — switching to ${AKS_NAME}"
  az aks get-credentials \
    --resource-group "${RG_NAME}" \
    --name "${AKS_NAME}" \
    --overwrite-existing \
    --output none
fi

# ── 4c. ACR image ─────────────────────────────────────────────────────────────

IMAGE_TAG="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"

EXISTING_TAG="$(az acr repository show-tags \
  --name "${ACR_NAME}" \
  --repository testfixtures \
  --query "[?@=='${IMAGE_TAG}']" \
  -o tsv 2>/dev/null || true)"

if [[ -z "${EXISTING_TAG}" ]]; then
  fix "ACR image testfixtures:${IMAGE_TAG} not found — building and pushing..."
  bash "${SCRIPTS_DIR}/acr-build.sh" "${IMAGE_TAG}"
fi

echo "[preflight] done."
