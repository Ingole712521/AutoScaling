#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib/common.sh"

emqx_run_pwsh "${ROOT}/scripts/run_validation_suite.ps1" "$@"
