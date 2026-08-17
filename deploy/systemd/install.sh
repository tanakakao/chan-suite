#!/usr/bin/env sh
set -eu

DRY_RUN=0
START_NOW=0

usage() {
  cat <<'EOF'
Usage: install.sh [--dry-run] [--now] [Local|Intranet] [server-host]

Installs and enables chan-suite.service for Linux systemd.

Options:
  --dry-run  Render the generated service/environment without installing it.
  --now      Safely stop managed chan-suite processes and start/restart the service now.

Examples:
  sh ./deploy/systemd/install.sh Intranet chan-server
  sh ./deploy/systemd/install.sh --now Intranet chan-server
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --now)
      START_NOW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "[ERROR] Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

PROFILE=${1:-Intranet}
SERVER_HOST=${2:-${CHAN_SERVER_HOST:-}}

case "$PROFILE" in
  Local)
    SERVER_HOST=
    ;;
  Intranet)
    if [ -z "$SERVER_HOST" ]; then
      echo "[ERROR] Intranet profile requires server-host or CHAN_SERVER_HOST."
      usage
      exit 1
    fi
    case "$SERVER_HOST" in
      *[!A-Za-z0-9._:-]*)
        echo "[ERROR] server-host contains unsupported characters: $SERVER_HOST"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "[ERROR] Profile must be Local or Intranet."
    exit 1
    ;;
esac

if [ "$(uname -s)" != "Linux" ]; then
  echo "[ERROR] systemd autostart installation is supported only on Linux."
  exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
SERVICE_NAME=chan-suite
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
ENV_DIR=/etc/chan-suite
ENV_FILE="$ENV_DIR/$SERVICE_NAME.env"
SERVICE_USER=$(id -un)
SERVICE_HOME=${HOME:-}

if [ -z "$SERVICE_HOME" ]; then
  echo "[ERROR] HOME is not set for service user $SERVICE_USER."
  exit 1
fi

if command -v pnpm >/dev/null 2>&1; then
  PNPM_BIN=$(command -v pnpm)
elif [ "$DRY_RUN" -eq 1 ]; then
  PNPM_BIN=/usr/bin/pnpm
else
  echo "[ERROR] pnpm was not found on PATH. Run setup_all.sh after installing pnpm."
  exit 1
fi

if command -v node >/dev/null 2>&1; then
  NODE_BIN=$(command -v node)
elif [ "$DRY_RUN" -eq 1 ]; then
  NODE_BIN=/usr/bin/node
else
  echo "[ERROR] node was not found on PATH."
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  HOST_PYTHON=$(command -v python3)
elif command -v python >/dev/null 2>&1; then
  HOST_PYTHON=$(command -v python)
elif [ "$DRY_RUN" -eq 1 ]; then
  HOST_PYTHON=/usr/bin/python3
else
  echo "[ERROR] Python was not found on PATH."
  exit 1
fi

SERVICE_PATH="$(dirname -- "$PNPM_BIN"):$(dirname -- "$NODE_BIN"):$(dirname -- "$HOST_PYTHON"):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ "$PROFILE" = "Intranet" ]; then
  START_ARGS="Intranet $SERVER_HOST"
else
  START_ARGS=Local
fi

UNIT_CONTENT=$(cat <<EOF
[Unit]
Description=chan-suite applications
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$SERVICE_USER
WorkingDirectory=$SUITE_ROOT
EnvironmentFile=$ENV_FILE
ExecStart=/bin/sh "$SUITE_ROOT/deploy/start_all.sh" $START_ARGS
ExecStop=/bin/sh "$SUITE_ROOT/deploy/stop_all.sh"
TimeoutStartSec=180
TimeoutStopSec=90
KillMode=control-group
NoNewPrivileges=true
UMask=0027

[Install]
WantedBy=multi-user.target
EOF
)

ENV_CONTENT=$(cat <<EOF
HOME=$SERVICE_HOME
USER=$SERVICE_USER
LOGNAME=$SERVICE_USER
PATH=$SERVICE_PATH
EOF
)

if [ "$DRY_RUN" -eq 1 ]; then
  echo "===== $SERVICE_FILE ====="
  printf '%s\n' "$UNIT_CONTENT"
  echo "===== $ENV_FILE ====="
  printf '%s\n' "$ENV_CONTENT"
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "[ERROR] Run this installer as the Linux account that owns chan-suite, without sudo."
  echo "        The script will request sudo only when writing systemd configuration."
  exit 1
fi
if ! command -v sudo >/dev/null 2>&1; then
  echo "[ERROR] sudo was not found. Installing a system service requires administrator privileges."
  exit 1
fi
if ! command -v systemctl >/dev/null 2>&1; then
  echo "[ERROR] systemctl was not found. This server may not use systemd."
  exit 1
fi

sudo mkdir -p "$ENV_DIR"
printf '%s\n' "$ENV_CONTENT" | sudo tee "$ENV_FILE" >/dev/null
sudo chmod 0644 "$ENV_FILE"
printf '%s\n' "$UNIT_CONTENT" | sudo tee "$SERVICE_FILE" >/dev/null
sudo chmod 0644 "$SERVICE_FILE"
sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME.service"

echo "[OK] Installed and enabled $SERVICE_NAME.service."
echo "     It will start automatically on the next server boot."

if [ "$START_NOW" -eq 1 ]; then
  echo "[INFO] Stopping currently managed chan-suite processes before handing control to systemd."
  if ! sh "$SUITE_ROOT/deploy/stop_all.sh"; then
    echo "[ERROR] Managed shutdown did not complete safely. The systemd service was enabled but not started."
    exit 1
  fi
  sudo systemctl restart "$SERVICE_NAME.service"
  echo "[OK] $SERVICE_NAME.service is now running."
else
  echo "[INFO] Current processes were left unchanged."
  echo "       To hand control to systemd now, rerun with --now."
fi

echo "Status : sudo systemctl status $SERVICE_NAME.service"
echo "Enabled: systemctl is-enabled $SERVICE_NAME.service"
echo "Logs   : journalctl -u $SERVICE_NAME.service"
