#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

MQTT_HOST="${MQTT_HOST:-}"
FROM_TERRAFORM="${FROM_TERRAFORM:-false}"
TERRAFORM_DIR="${TERRAFORM_DIR:-.}"
PUBLISH_INTERVAL="${PUBLISH_INTERVAL:-}"
PAYLOAD_SIZE="${PAYLOAD_SIZE:-}"

if [[ "${FROM_TERRAFORM}" == "true" ]]; then
  if ! command -v terraform >/dev/null 2>&1; then
    echo "terraform is required for FROM_TERRAFORM=true"
    exit 1
  fi
  for name in mqtt_nlb_dns_name nlb_dns_name; do
    if host="$(terraform -chdir="${TERRAFORM_DIR}" output -raw "${name}" 2>/dev/null)"; then
      MQTT_HOST="${host}"
      break
    fi
  done
fi

if [[ -z "${MQTT_HOST}" ]]; then
  echo "Set MQTT_HOST or run with FROM_TERRAFORM=true after terraform apply."
  echo "Example: FROM_TERRAFORM=true ./scripts/run_staged_load_test.sh"
  exit 1
fi

PYTHON="$("${ROOT}/scripts/lib/ensure_venv.sh" "${ROOT}")"
"${PYTHON}" -m pip install -q -r loadtest/requirements.txt
ARGS=(loadtest/staged_load.py --host "${MQTT_HOST}")

if [[ -n "${PUBLISH_INTERVAL}" ]]; then
  ARGS+=(--publish-interval "${PUBLISH_INTERVAL}")
fi

if [[ -n "${PAYLOAD_SIZE}" ]]; then
  ARGS+=(--payload-size "${PAYLOAD_SIZE}")
fi

echo "Running staged load test against ${MQTT_HOST}"
"${PYTHON}" "${ARGS[@]}"