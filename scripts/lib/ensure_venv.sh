#!/usr/bin/env bash
# Ensure project .venv exists on macOS/Linux (PEP 668 safe). Prints python path to stdout.
set -euo pipefail

_ensure_venv_root="${1:?project root required}"
cd "${_ensure_venv_root}"

if [[ "${OS:-}" == "Windows_NT" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
  else
    command -v python
  fi
  exit 0
fi

if [[ ! -x "${_ensure_venv_root}/.venv/bin/python" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required (macOS: brew install python)" >&2
    exit 1
  fi
  echo "Creating Python virtual environment at .venv (required on macOS/Linux)..." >&2
  python3 -m venv "${_ensure_venv_root}/.venv"
fi

echo "${_ensure_venv_root}/.venv/bin/python"
