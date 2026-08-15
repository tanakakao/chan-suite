#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APPS_DIR="$SUITE_ROOT/apps"
FAILED=0

if ! command -v pnpm >/dev/null 2>&1; then
  echo "[ERROR] pnpm was not found on PATH."
  exit 1
fi

USE_UV=0
BASE_PYTHON=""
if command -v uv >/dev/null 2>&1; then
  USE_UV=1
elif command -v python3 >/dev/null 2>&1; then
  BASE_PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  BASE_PYTHON=python
else
  echo "[ERROR] Neither uv nor Python was found on PATH."
  exit 1
fi

find_venv_python() {
  if [ -x "$1/.venv/bin/python" ]; then
    printf '%s\n' "$1/.venv/bin/python"
  elif [ -x "$1/.venv/Scripts/python.exe" ]; then
    printf '%s\n' "$1/.venv/Scripts/python.exe"
  else
    return 1
  fi
}

setup_python() {
  app=$1
  spec=$2
  app_dir="$APPS_DIR/$app"
  if [ ! -f "$app_dir/pyproject.toml" ]; then
    echo "[SKIP] $app Python: pyproject.toml not found."
    return
  fi

  if ! venv_python=$(find_venv_python "$app_dir"); then
    echo "[SETUP] $app Python virtual environment"
    if [ "$USE_UV" -eq 1 ]; then
      (cd "$app_dir" && uv venv .venv) || { echo "[ERROR] $app: failed to create .venv."; FAILED=1; return; }
    else
      (cd "$app_dir" && "$BASE_PYTHON" -m venv .venv) || { echo "[ERROR] $app: failed to create .venv."; FAILED=1; return; }
    fi
    venv_python=$(find_venv_python "$app_dir") || { echo "[ERROR] $app: .venv Python was not found after creation."; FAILED=1; return; }
  fi

  echo "[SETUP] $app Python dependencies: $spec"
  if [ "$USE_UV" -eq 1 ]; then
    (cd "$app_dir" && uv pip install --python "$venv_python" --upgrade -e "$spec") || { echo "[ERROR] $app: Python dependency installation failed."; FAILED=1; return; }
  else
    (cd "$app_dir" && "$venv_python" -m pip install --upgrade pip && "$venv_python" -m pip install --upgrade -e "$spec") || { echo "[ERROR] $app: Python dependency installation failed."; FAILED=1; return; }
  fi
  echo "[OK] $app Python"
}

setup_frontend() {
  app=$1
  relative_dir=$2
  app_dir="$APPS_DIR/$app"
  if [ "$relative_dir" = "." ]; then
    frontend_dir=$app_dir
  else
    frontend_dir="$app_dir/$relative_dir"
  fi

  if [ ! -f "$frontend_dir/package.json" ]; then
    echo "[SKIP] $app frontend: package.json not found."
    return
  fi
  if [ ! -f "$frontend_dir/pnpm-lock.yaml" ]; then
    echo "[ERROR] $app frontend: pnpm-lock.yaml not found."
    FAILED=1
    return
  fi

  echo "[SETUP] $app frontend"
  (cd "$frontend_dir" && pnpm install --frozen-lockfile) || { echo "[ERROR] $app: pnpm install failed."; FAILED=1; return; }
  echo "[OK] $app frontend"
}

setup_frontend chan-portal .
setup_python bochan '.[web]'
setup_frontend bochan web
setup_python malchan '.[web,models,inverse,visualization]'
setup_frontend malchan frontend
setup_python cauchan .
setup_frontend cauchan web
setup_python dchan .
setup_frontend dchan frontend

if [ "$FAILED" -ne 0 ]; then
  echo "[ERROR] One or more application setups failed."
  exit 1
fi

echo "[OK] All available applications are set up."
