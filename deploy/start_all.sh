#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APPS_DIR="$SUITE_ROOT/apps"
LOGS_DIR="$SUITE_ROOT/logs"
PROFILE=${1:-Local}
SERVER_HOST=${2:-${CHAN_SERVER_HOST:-}}
FAILED=0

case "$PROFILE" in
  Local)
    BIND_HOST=127.0.0.1
    PUBLIC_HOST=127.0.0.1
    ;;
  Intranet)
    BIND_HOST=0.0.0.0
    if [ -z "$SERVER_HOST" ]; then
      echo "[ERROR] Intranet profile requires server-host or CHAN_SERVER_HOST."
      echo "Usage: $0 Intranet <server-host>"
      exit 1
    fi
    PUBLIC_HOST=$SERVER_HOST
    ;;
  *)
    echo "[ERROR] Profile must be Local or Intranet."
    exit 1
    ;;
esac

if ! command -v pnpm >/dev/null 2>&1; then
  echo "[ERROR] pnpm was not found on PATH. Run setup_all.sh after installing pnpm."
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  HOST_PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  HOST_PYTHON=python
else
  echo "[ERROR] Python was not found on PATH."
  exit 1
fi

PORT_ASSIGNMENTS=$(
  "$HOST_PYTHON" - "$SUITE_ROOT/config/apps.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    applications = {item["name"]: item for item in json.load(stream)["applications"]}

mapping = {
    "chan-portal": "PORTAL",
    "bochan": "BOCHAN",
    "malchan": "MALCHAN",
    "cauchan": "CAUCHAN",
    "dchan": "DCHAN",
}
for name, prefix in mapping.items():
    app = applications[name]
    frontend = app.get("frontendPort")
    backend = app.get("backendPort")
    if frontend is None:
        raise SystemExit(f"frontendPort is missing for {name}")
    print(f"{prefix}_FRONTEND={int(frontend)}")
    if backend is not None:
        print(f"{prefix}_BACKEND={int(backend)}")
PY
) || {
  echo "[ERROR] Failed to read config/apps.json."
  exit 1
}
eval "$PORT_ASSIGNMENTS"

mkdir -p "$LOGS_DIR"

port_in_use() {
  "$HOST_PYTHON" -c 'import socket,sys; s=socket.socket(); s.settimeout(0.2); code=s.connect_ex(("127.0.0.1", int(sys.argv[1]))); s.close(); raise SystemExit(0 if code == 0 else 1)' "$1" >/dev/null 2>&1
}

find_venv_python() {
  if [ -x "$1/.venv/bin/python" ]; then
    printf '%s\n' "$1/.venv/bin/python"
  elif [ -x "$1/.venv/Scripts/python.exe" ]; then
    printf '%s\n' "$1/.venv/Scripts/python.exe"
  else
    return 1
  fi
}

start_bg() {
  name=$1
  working_dir=$2
  shift 2
  if [ ! -d "$working_dir" ]; then
    echo "[SKIP] $name: directory not found."
    FAILED=1
    return
  fi
  echo "[START] $name"
  (
    cd "$working_dir" || exit 1
    nohup "$@" >"$LOGS_DIR/$name.log" 2>"$LOGS_DIR/$name.error.log" &
    echo $! >"$LOGS_DIR/$name.pid"
  ) || {
    echo "[ERROR] $name: failed to launch."
    FAILED=1
    return
  }
}

start_frontend() {
  name=$1
  port=$2
  working_dir=$3
  shift 3
  if port_in_use "$port"; then
    echo "[RUNNING] $name: port $port is already in use."
    return
  fi
  if [ ! -f "$working_dir/pnpm-lock.yaml" ]; then
    echo "[ERROR] $name: pnpm-lock.yaml not found. Run setup_all.sh after updating repositories."
    FAILED=1
    return
  fi
  start_bg "$name" "$working_dir" "$@" pnpm run dev -- --host "$BIND_HOST" --port "$port" --strictPort
}

PORTAL="$APPS_DIR/chan-portal"
BOCHAN="$APPS_DIR/bochan"
MALCHAN="$APPS_DIR/malchan"
CAUCHAN="$APPS_DIR/cauchan"
DCHAN="$APPS_DIR/dchan"

COMMON_PROFILE="CHAN_SUITE_PROFILE=$PROFILE"
COMMON_BIND="CHAN_BIND_HOST=$BIND_HOST"
COMMON_PUBLIC="CHAN_PUBLIC_HOST=$PUBLIC_HOST"

start_frontend chan-portal "$PORTAL_FRONTEND" "$PORTAL" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=$PORTAL_FRONTEND" \
  "VITE_BOCHAN_URL=http://$PUBLIC_HOST:$BOCHAN_FRONTEND" \
  "VITE_MALCHAN_URL=http://$PUBLIC_HOST:$MALCHAN_FRONTEND" \
  "VITE_CAUCHAN_URL=http://$PUBLIC_HOST:$CAUCHAN_FRONTEND" \
  "VITE_DCHAN_URL=http://$PUBLIC_HOST:$DCHAN_FRONTEND"

if ! bochan_python=$(find_venv_python "$BOCHAN" 2>/dev/null); then
  echo "[ERROR] bochan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use "$BOCHAN_BACKEND"; then
  echo "[RUNNING] bochan-backend: port $BOCHAN_BACKEND is already in use."
else
  start_bg bochan-backend "$BOCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=$BOCHAN_FRONTEND" "CHAN_BACKEND_PORT=$BOCHAN_BACKEND" \
    PYTHONUNBUFFERED=1 \
    "$bochan_python" -m uvicorn bochan.serving.webapp.app:app --host "$BIND_HOST" --port "$BOCHAN_BACKEND"
fi
start_frontend bochan-frontend "$BOCHAN_FRONTEND" "$BOCHAN/web" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=$BOCHAN_FRONTEND" "CHAN_BACKEND_PORT=$BOCHAN_BACKEND" \
  "VITE_API_BASE=/api/v1"

if ! malchan_python=$(find_venv_python "$MALCHAN" 2>/dev/null); then
  echo "[ERROR] malchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use "$MALCHAN_BACKEND"; then
  echo "[RUNNING] malchan-backend: port $MALCHAN_BACKEND is already in use."
else
  start_bg malchan-backend "$MALCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=$MALCHAN_FRONTEND" "CHAN_BACKEND_PORT=$MALCHAN_BACKEND" \
    "MALCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:$MALCHAN_FRONTEND,http://localhost:$MALCHAN_FRONTEND" \
    PYTHONUNBUFFERED=1 \
    "$malchan_python" -m uvicorn "malchan.app:create_app" --factory --host "$BIND_HOST" --port "$MALCHAN_BACKEND"
fi
start_frontend malchan-frontend "$MALCHAN_FRONTEND" "$MALCHAN/frontend" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=$MALCHAN_FRONTEND" "CHAN_BACKEND_PORT=$MALCHAN_BACKEND" \
  "VITE_API_BASE=http://$PUBLIC_HOST:$MALCHAN_BACKEND/api"

if ! cauchan_python=$(find_venv_python "$CAUCHAN" 2>/dev/null); then
  echo "[ERROR] cauchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use "$CAUCHAN_BACKEND"; then
  echo "[RUNNING] cauchan-backend: port $CAUCHAN_BACKEND is already in use."
else
  start_bg cauchan-backend "$CAUCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=$CAUCHAN_FRONTEND" "CHAN_BACKEND_PORT=$CAUCHAN_BACKEND" \
    "CAUCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:$CAUCHAN_FRONTEND,http://localhost:$CAUCHAN_FRONTEND" \
    PYTHONUNBUFFERED=1 \
    "$cauchan_python" -m uvicorn cauchan.api.app:app --app-dir "$CAUCHAN/src" --host "$BIND_HOST" --port "$CAUCHAN_BACKEND"
fi
start_frontend cauchan-frontend "$CAUCHAN_FRONTEND" "$CAUCHAN/web" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=$CAUCHAN_FRONTEND" "CHAN_BACKEND_PORT=$CAUCHAN_BACKEND" \
  "VITE_API_BASE_URL=http://$PUBLIC_HOST:$CAUCHAN_BACKEND/api/v1"

if ! dchan_python=$(find_venv_python "$DCHAN" 2>/dev/null); then
  echo "[ERROR] dchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use "$DCHAN_BACKEND"; then
  echo "[RUNNING] dchan-backend: port $DCHAN_BACKEND is already in use."
else
  start_bg dchan-backend "$DCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=$DCHAN_FRONTEND" "CHAN_BACKEND_PORT=$DCHAN_BACKEND" \
    "DCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:$DCHAN_FRONTEND,http://localhost:$DCHAN_FRONTEND" \
    PYTHONUNBUFFERED=1 \
    "$dchan_python" -m uvicorn application.main:app --host "$BIND_HOST" --port "$DCHAN_BACKEND"
fi
start_frontend dchan-frontend "$DCHAN_FRONTEND" "$DCHAN/frontend" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=$DCHAN_FRONTEND" "CHAN_BACKEND_PORT=$DCHAN_BACKEND" \
  "VITE_API_URL=http://$PUBLIC_HOST:$DCHAN_BACKEND"

echo
echo "Portal: http://$PUBLIC_HOST:$PORTAL_FRONTEND"
echo "bochan: http://$PUBLIC_HOST:$BOCHAN_FRONTEND"
echo "malchan: http://$PUBLIC_HOST:$MALCHAN_FRONTEND"
echo "cauchan: http://$PUBLIC_HOST:$CAUCHAN_FRONTEND"
echo "dchan: http://$PUBLIC_HOST:$DCHAN_FRONTEND"
echo "Logs: $LOGS_DIR"

if [ "$FAILED" -ne 0 ]; then
  echo "[ERROR] One or more applications could not be launched."
  exit 1
fi

echo "[OK] Launch commands were issued for all applications."
