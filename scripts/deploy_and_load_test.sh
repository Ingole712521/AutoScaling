#!/usr/bin/env bash
# Wrapper for Git Bash / WSL: runs the PowerShell deploy script on Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v pwsh >/dev/null 2>&1; then
  exec pwsh -NoProfile -File "$ROOT/scripts/deploy_and_load_test.ps1" "$@"
elif command -v powershell.exe >/dev/null 2>&1; then
  exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/deploy_and_load_test.ps1" "$@"
else
  echo "PowerShell is required. Install PowerShell or run from Windows PowerShell:"
  echo '  .\scripts\deploy_and_load_test.ps1'
  exit 1
fi
