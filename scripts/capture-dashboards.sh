#!/usr/bin/env bash
# Port-forward Grafana and capture PNG screenshots of all four dashboards via
# the Grafana Render API (backed by the grafana-image-renderer sidecar).
# Saves files to docs/screenshots/.
#
# Usage:
#   ./scripts/capture-dashboards.sh [--from <time>] [--to <time>]
#
# --from / --to default to "now-1h" / "now" and are passed straight to Grafana
# so any Grafana-relative time expression works (e.g. now-3h, now-6h, now).
#
# Prerequisites:
#   - kubectl configured for the target cluster (run azure-deploy.sh first)
#   - curl

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${REPO_ROOT}/docs/screenshots"
GRAFANA_NS="testfixtures-monitoring"
LOCAL_PORT="3000"
GRAFANA_URL="http://localhost:${LOCAL_PORT}"
GRAFANA_CREDS="admin:admin"
FROM="now-1h"
TO="now"
WIDTH=1920
HEIGHT=1080

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) FROM="$2"; shift 2 ;;
    --to)   TO="$2";   shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "${OUT_DIR}"

# ── Port-forward ──────────────────────────────────────────────────────────────

echo "==> Starting port-forward to Grafana (${GRAFANA_NS}/svc/grafana:3000)..."
kubectl port-forward svc/grafana "${LOCAL_PORT}:3000" \
  --namespace "${GRAFANA_NS}" &
PF_PID=$!
trap 'echo "==> Stopping port-forward (PID ${PF_PID})"; kill "${PF_PID}" 2>/dev/null || true' EXIT

# ── Wait for Grafana to be reachable ─────────────────────────────────────────

echo "==> Waiting for Grafana health..."
for i in $(seq 1 30); do
  if curl -sf -u "${GRAFANA_CREDS}" "${GRAFANA_URL}/api/health" >/dev/null 2>&1; then
    echo "    Ready after ${i}s"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: Grafana did not become healthy within 30s" >&2
    exit 1
  fi
  sleep 1
done

# ── Wait for image renderer ───────────────────────────────────────────────────
# The renderer exposes a /render/version endpoint on port 8081 inside the pod.
# Poll it via the Grafana health check which reports renderer state, then do a
# trial render of a 1x1 pixel PNG to confirm it is actually serving images.

echo "==> Waiting for image renderer..."
RENDERER_OK=0
PDF_STREAK=0
for i in $(seq 1 60); do
  # A successful render returns PNG magic bytes; PDF or HTML means not ready
  # (or, on some grafana-image-renderer:latest builds, means the renderer is
  # up but mis-encoding — see the PDF_STREAK fail-fast below).
  RESPONSE=$(curl -sf -u "${GRAFANA_CREDS}" --max-time 30 \
    "${GRAFANA_URL}/render/d/tf-pipeline-overview/pipeline-overview?orgId=1&width=100&height=100&from=now-5m&to=now" \
    2>/dev/null || true)
  MAGIC="${RESPONSE:0:4}"
  if [[ "${MAGIC}" == $'\x89PNG' ]]; then
    echo "    Renderer ready after ${i} attempt(s)"
    RENDERER_OK=1
    break
  fi
  if [[ "${MAGIC}" == "%PDF" ]]; then
    PDF_STREAK=$((PDF_STREAK + 1))
    # 3 consecutive PDF responses means the renderer is up and answering but
    # mis-encoding every request — retrying won't fix that, so stop burning
    # ~20s/attempt and fail fast with a diagnosis instead of spinning for
    # the full 60-attempt budget (which can take 15-20+ minutes at this
    # renderer's ~20s-per-request latency).
    if [[ ${PDF_STREAK} -ge 3 ]]; then
      echo "ERROR: renderer is responding but returning PDF content instead of PNG" >&2
      echo "       (Content-Type may still say image/png — this is a renderer-side" >&2
      echo "       encoding bug, not a readiness issue). Seen on" >&2
      echo "       grafana/grafana-image-renderer:latest as of 2026-08-21; retrying" >&2
      echo "       will not help. Known workaround: capture screenshots with a" >&2
      echo "       real browser against the dashboard URLs directly instead of" >&2
      echo "       this script. Pinning the renderer to an older, known-good tag" >&2
      echo "       may also resolve it — untested here." >&2
      exit 1
    fi
  else
    PDF_STREAK=0
  fi
  sleep 1
done

if [[ ${RENDERER_OK} -eq 0 ]]; then
  echo "ERROR: image renderer is not returning PNG after 60 attempts." >&2
  echo "       Check that grafana-image-renderer sidecar is running:" >&2
  echo "       kubectl get pods -n ${GRAFANA_NS}" >&2
  exit 1
fi

# ── Capture each dashboard ────────────────────────────────────────────────────

# SLUG:UID pairs — bash 3.2 compatible (no associative arrays)
DASHBOARD_PAIRS="
pipeline-overview:tf-pipeline-overview
app-metrics:tf-app-metrics
database-metrics:tf-database-metrics
kafka-metrics:tf-kafka-metrics
"

echo ""
echo "==> Capturing dashboards (from=${FROM}, to=${TO}, ${WIDTH}x${HEIGHT})..."

FAILED=0
for PAIR in ${DASHBOARD_PAIRS}; do
  SLUG="${PAIR%%:*}"
  DASH_UID="${PAIR##*:}"
  OUTFILE="${OUT_DIR}/${SLUG}.png"

  RENDER_URL="${GRAFANA_URL}/render/d/${DASH_UID}/${SLUG}"
  RENDER_URL+="?orgId=1&from=${FROM}&to=${TO}"
  RENDER_URL+="&width=${WIDTH}&height=${HEIGHT}&tz=UTC"

  echo -n "    ${SLUG} ... "
  HTTP_STATUS=$(curl -sf -u "${GRAFANA_CREDS}" \
    --max-time 60 \
    -w "%{http_code}" \
    -o "${OUTFILE}" \
    "${RENDER_URL}" 2>/dev/null || echo "000")

  MAGIC=$(head -c 4 "${OUTFILE}" 2>/dev/null || true)
  if [[ "${HTTP_STATUS}" == "200" ]] && [[ "${MAGIC}" == $'\x89PNG' ]]; then
    SIZE=$(wc -c < "${OUTFILE}" | tr -d ' ')
    echo "OK (${SIZE} bytes) -> ${OUTFILE}"
  else
    echo "FAILED (HTTP ${HTTP_STATUS}, not a PNG)"
    rm -f "${OUTFILE}"
    FAILED=$((FAILED + 1))
  fi
done

echo ""
if [[ ${FAILED} -eq 0 ]]; then
  echo "==> All 4 screenshots saved to ${OUT_DIR}/"
  ls -lh "${OUT_DIR}/"
else
  echo "ERROR: ${FAILED} dashboard(s) failed to render." >&2
  echo "       Ensure the grafana-image-renderer sidecar is running:" >&2
  echo "       kubectl get pods -n ${GRAFANA_NS}" >&2
  exit 1
fi
