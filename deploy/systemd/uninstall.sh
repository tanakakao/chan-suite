#!/usr/bin/env sh
set -eu

SERVICE_NAME=chan-suite
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
ENV_FILE="/etc/chan-suite/$SERVICE_NAME.env"

if [ "$(uname -s)" != "Linux" ]; then
  echo "[ERROR] systemd autostart removal is supported only on Linux."
  exit 1
fi

run_admin() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    if ! command -v sudo >/dev/null 2>&1; then
      echo "[ERROR] sudo was not found. Removing a system service requires administrator privileges."
      exit 1
    fi
    sudo "$@"
  fi
}

if command -v systemctl >/dev/null 2>&1; then
  run_admin systemctl disable --now "$SERVICE_NAME.service" 2>/dev/null || true
fi

run_admin rm -f "$SERVICE_FILE" "$ENV_FILE"
run_admin rmdir /etc/chan-suite 2>/dev/null || true

if command -v systemctl >/dev/null 2>&1; then
  run_admin systemctl daemon-reload
  run_admin systemctl reset-failed "$SERVICE_NAME.service" 2>/dev/null || true
fi

echo "[OK] Removed $SERVICE_NAME.service autostart configuration."
