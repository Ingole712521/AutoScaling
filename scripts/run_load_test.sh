#!/usr/bin/env bash
set -euo pipefail

if ! command -v k6 >/dev/null 2>&1; then
  echo "k6 is required. Install from https://k6.io/docs/get-started/installation/"
  exit 1
fi

if [ ! -f "loadtest/mqtt-k6.js" ]; then
  echo "loadtest/mqtt-k6.js not found."
  exit 1
fi

MQTT_HOST="${MQTT_HOST:-}"
VUS="${VUS:-25000}"
DURATION="${DURATION:-15m}"

if [ -z "${MQTT_HOST}" ]; then
  echo "Set MQTT_HOST environment variable to NLB DNS name."
  echo "Example: MQTT_HOST=your-nlb.amazonaws.com ./scripts/run_load_test.sh"
  exit 1
fi

echo "Running load test against ${MQTT_HOST} with VUS=${VUS}, DURATION=${DURATION}"
k6 run -e MQTT_HOST="${MQTT_HOST}" -e VUS="${VUS}" -e DURATION="${DURATION}" loadtest/mqtt-k6.js
