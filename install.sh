#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR"

START_AFTER_SETUP=0
case "${1:-}" in
  "") ;;
  --start) START_AFTER_SETUP=1 ;;
  *)
    echo "Usage: sh ./install.sh [--start]" >&2
    exit 2
    ;;
esac

echo "========================================"
echo "chan-suite initial setup"
echo "========================================"
echo

echo "Checking required tools..."
missing=0
for tool in git uv node pnpm; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "[OK] $tool"
  else
    echo "[MISSING] $tool"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo
  echo "[ERROR] Required tools are missing." >&2
  echo "Install the tools shown above and run install.sh again." >&2
  exit 1
fi

echo
echo "[1/2] Cloning chan repositories..."
sh "$SCRIPT_DIR/deploy/clone_all.sh" || {
  echo >&2
  echo "[ERROR] Repository clone step failed." >&2
  exit 1
}

echo
echo "[2/2] Creating locked application environments..."
sh "$SCRIPT_DIR/deploy/setup_all.sh" || {
  echo >&2
  echo "[ERROR] Environment setup failed." >&2
  exit 1
}

echo
echo "========================================"
echo "chan-suite setup completed successfully."
echo "========================================"
echo
echo "Start all applications later with:"
echo "  sh ./deploy/start_all.sh"

if [ "$START_AFTER_SETUP" -eq 1 ]; then
  echo
  echo "Starting all applications..."
  exec sh "$SCRIPT_DIR/deploy/start_all.sh"
fi
