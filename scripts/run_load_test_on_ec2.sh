#!/usr/bin/env bash
# Run MQTT load tests from an EC2 in the same VPC (Amazon Linux, Ubuntu, etc.).
# Terraform is NOT required on this machine — set MQTT_HOST (and optional ASG_NAME).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/lib/common.sh"

MODE="${1:-staged}"
MQTT_HOST="${MQTT_HOST:-}"
ASG_NAME="${ASG_NAME:-}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLIENTS="${CLIENTS:-100}"
export AWS_REGION AWS_DEFAULT_REGION="${AWS_REGION}"

usage() {
  cat <<'EOF'
Usage: ./scripts/run_load_test_on_ec2.sh [probe|staged|sustained]

Run from Amazon Linux / Ubuntu EC2 in the same VPC as EMQX.
Set these once (copy from your PC: bash ./scripts/print_load_test_env.sh):

  export MQTT_HOST=emqx-prod-mqtt-nlb-....elb.ap-south-1.amazonaws.com
  export ASG_NAME=emqx-prod-replicants-asg
  export AWS_REGION=ap-south-1

Examples:
  bash ./scripts/run_load_test_on_ec2.sh probe
  bash ./scripts/run_load_test_on_ec2.sh staged
  CLIENTS=200 bash ./scripts/run_load_test_on_ec2.sh sustained

Optional tuning (staged/sustained):
  PUBLISH_INTERVAL=0.001 PAYLOAD_SIZE=16384 MESSAGES_PER_BURST=10
  LOAD_STAGES=40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:90:scale-in

First time on EC2: bash ./scripts/setup_loadgen_amazon_linux.sh
EOF
}

case "${MODE}" in
  -h|--help|help) usage; exit 0 ;;
  probe|staged|sustained) ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    usage
    exit 1
    ;;
esac

if [[ -z "${MQTT_HOST}" ]]; then
  echo "MQTT_HOST is required on EC2 (no terraform needed)." >&2
  echo "On your PC (project root): bash ./scripts/print_load_test_env.sh" >&2
  usage
  exit 1
fi

PYTHON="$("${ROOT}/scripts/lib/ensure_venv.sh" "${ROOT}")"
"${PYTHON}" -m pip install -q -r loadtest/requirements.txt

echo "=== EMQX load test from EC2 ==="
echo "Mode:     ${MODE}"
echo "Target:   ${MQTT_HOST}:1883"
echo "Region:   ${AWS_REGION}"
if [[ -n "${ASG_NAME}" ]]; then
  echo "ASG:      ${ASG_NAME}"
else
  echo "ASG:      (not set — ASG polling disabled)"
fi
echo ""

case "${MODE}" in
  probe)
    exec "${PYTHON}" scripts/mqtt_probe.py --host "${MQTT_HOST}"
    ;;
  staged)
    export MQTT_HOST ASG_NAME
    export PUBLISH_INTERVAL="${PUBLISH_INTERVAL:-0.001}"
    export PAYLOAD_SIZE="${PAYLOAD_SIZE:-16384}"
    export MESSAGES_PER_BURST="${MESSAGES_PER_BURST:-10}"
    export LOAD_STAGES="${LOAD_STAGES:-40:180:baseline-heavy,80:300:scale-out-2,120:300:scale-out-3,10:90:scale-in}"
    exec bash "${ROOT}/scripts/run_staged_load_test.sh"
    ;;
  sustained)
    export MQTT_HOST ASG_NAME CLIENTS
    export PUBLISH_INTERVAL="${PUBLISH_INTERVAL:-0.01}"
    export PAYLOAD_SIZE="${PAYLOAD_SIZE:-8192}"
    export MESSAGES_PER_BURST="${MESSAGES_PER_BURST:-5}"
    exec bash "${ROOT}/scripts/run_sustained_load_test.sh"
    ;;
esac
