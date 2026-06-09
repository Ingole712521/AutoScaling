#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT}/scripts/lib/common.sh"

emqx_run_pwsh "${ROOT}/scripts/apply_cluster_fast_refresh.ps1" "$@"
