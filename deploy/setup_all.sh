#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APPS_DIR="$SUITE_ROOT/apps"
FAILED=0
PYTHON_VERSION=${CHAN_PYTHON_VERSION:-3.12}

if ! command -v pnpm >/dev/null 2>&1; then
  echo "[ERROR] pnpm was not found on PATH."
  exit 1
fi
if ! command -v uv >/dev/null 2>&1; then
  echo "[ERROR] uv was not found on PATH."
  echo "Python environments in chan-suite are managed from each repository's uv.lock."
  exit 1
fi

setup_python() {
  app=$1
  profile=$2
  app_dir="$APPS_DIR/$app"
  if [ ! -f "$app_dir/pyproject.toml" ]; then
    echo "[SKIP] $app Python: pyproject.toml not found."
    return
  fi
  if [ ! -f "$app_dir/uv.lock" ]; then
    echo "[ERROR] $app Python: uv.lock not found."
    echo "        Update the repository; do not generate a deployment lockfile implicitly."
    FAILED=1
    return
  fi

  echo "[SETUP] $app Python $PYTHON_VERSION from uv.lock"
  case "$profile" in
    bochan-web)
      (cd "$app_dir" && uv sync --locked --python "$PYTHON_VERSION" --extra web) || { echo "[ERROR] $app: uv sync --locked failed."; FAILED=1; return; }
      ;;
    malchan-web)
      (cd "$app_dir" && uv sync --locked --python "$PYTHON_VERSION" --extra web --extra models --extra inverse --extra visualization) || { echo "[ERROR] $app: uv sync --locked failed."; FAILED=1; return; }
      ;;
    core)
      (cd "$app_dir" && uv sync --locked --python "$PYTHON_VERSION") || { echo "[ERROR] $app: uv sync --locked failed."; FAILED=1; return; }
      ;;
    *)
      echo "[ERROR] $app: unknown setup profile: $profile"
      FAILED=1
      return
      ;;
  esac
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

  echo "[SETUP] $app frontend from pnpm-lock.yaml"
  (cd "$frontend_dir" && pnpm install --frozen-lockfile) || { echo "[ERROR] $app: pnpm install failed."; FAILED=1; return; }
  echo "[OK] $app frontend"
}

setup_frontend chan-portal .
setup_python bochan bochan-web
setup_frontend bochan web
setup_python malchan malchan-web
setup_frontend malchan frontend
setup_python cauchan core
setup_frontend cauchan web
setup_python dchan core
setup_frontend dchan frontend

if [ "$FAILED" -ne 0 ]; then
  echo "[ERROR] One or more application setups failed."
  exit 1
fi

echo "[OK] All available applications are set up from committed lockfiles."
