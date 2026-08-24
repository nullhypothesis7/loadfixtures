#!/usr/bin/env bash
# Run the end-to-end test against the deployed AKS stack.
# Port-forwards the app, fires smoke-test + banking pipes, polls until DONE.
#
# Usage:
#   ./scripts/run-e2e.sh

set -euo pipefail

APP_NS="testfixtures"
APP_PORT="8080"
APP_URL="http://localhost:${APP_PORT}"
POLL_INTERVAL=5
PIPE_TIMEOUT=120

# ── Port-forward app ──────────────────────────────────────────────────────────

echo "==> Starting port-forward to testfixtures-app..."
kubectl port-forward svc/testfixtures-app "${APP_PORT}:8080" \
  --namespace "${APP_NS}" &
PF_PID=$!
trap 'echo "==> Stopping port-forward (PID ${PF_PID})"; kill "${PF_PID}" 2>/dev/null || true' EXIT

echo "==> Waiting for app health..."
for i in $(seq 1 30); do
  if curl -sf "${APP_URL}/actuator/health" >/dev/null 2>&1; then
    echo "    App ready after ${i}s"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: app did not become healthy within 30s" >&2
    exit 1
  fi
  sleep 1
done

# ── Helper: fire a pipe and poll until DONE ───────────────────────────────────

run_pipe() {
  local PIPE_NAME="$1"
  echo ""
  echo "==> Running pipe: ${PIPE_NAME}"

  local RUN_ID
  RUN_ID=$(curl -sf -X POST "${APP_URL}/api/runs" \
    -H "Content-Type: application/json" \
    -d "{\"pipeName\": \"${PIPE_NAME}\"}" \
    | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [[ -z "${RUN_ID}" ]]; then
    echo "ERROR: failed to start pipe ${PIPE_NAME}" >&2
    return 1
  fi
  echo "    Run ID: ${RUN_ID}"

  local ELAPSED=0
  while true; do
    local STATUS
    STATUS=$(curl -sf "${APP_URL}/api/runs/${RUN_ID}" \
      | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "UNKNOWN")

    echo "    [${ELAPSED}s] status: ${STATUS}"

    case "${STATUS}" in
      DONE)
        echo "    PASSED: ${PIPE_NAME} completed successfully"
        return 0
        ;;
      FAILED|ERROR)
        echo "ERROR: ${PIPE_NAME} failed (status: ${STATUS})" >&2
        return 1
        ;;
    esac

    if [[ ${ELAPSED} -ge ${PIPE_TIMEOUT} ]]; then
      echo "ERROR: ${PIPE_NAME} timed out after ${PIPE_TIMEOUT}s" >&2
      return 1
    fi
    sleep "${POLL_INTERVAL}"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
  done
}

# ── Run pipes ─────────────────────────────────────────────────────────────────

FAILED=0

run_pipe "smoke-test"      || FAILED=$((FAILED + 1))
run_pipe "banking-customers" || FAILED=$((FAILED + 1))
run_pipe "banking-accounts"  || FAILED=$((FAILED + 1))
run_pipe "banking-transactions" || FAILED=$((FAILED + 1))

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
if [[ ${FAILED} -eq 0 ]]; then
  echo "==> E2E PASSED: all pipes completed successfully"
else
  echo "==> E2E FAILED: ${FAILED} pipe(s) did not complete" >&2
  exit 1
fi
