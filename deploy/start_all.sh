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

start_frontend chan-portal 5172 "$PORTAL" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=5172" \
  "VITE_BOCHAN_URL=http://$PUBLIC_HOST:5173" \
  "VITE_MALCHAN_URL=http://$PUBLIC_HOST:5174" \
  "VITE_CAUCHAN_URL=http://$PUBLIC_HOST:5175" \
  "VITE_DCHAN_URL=http://$PUBLIC_HOST:5176"

if ! bochan_python=$(find_venv_python "$BOCHAN" 2>/dev/null); then
  echo "[ERROR] bochan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use 8001; then
  echo "[RUNNING] bochan-backend: port 8001 is already in use."
else
  start_bg bochan-backend "$BOCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=5173" "CHAN_BACKEND_PORT=8001" \
    PYTHONUNBUFFERED=1 \
    "$bochan_python" -m uvicorn bochan.serving.webapp.app:app --host "$BIND_HOST" --port 8001
fi
start_frontend bochan-frontend 5173 "$BOCHAN/web" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=5173" "CHAN_BACKEND_PORT=8001" \
  "VITE_API_BASE=/api/v1"

if ! malchan_python=$(find_venv_python "$MALCHAN" 2>/dev/null); then
  echo "[ERROR] malchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use 8002; then
  echo "[RUNNING] malchan-backend: port 8002 is already in use."
else
  start_bg malchan-backend "$MALCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=5174" "CHAN_BACKEND_PORT=8002" \
    "MALCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:5174,http://localhost:5174" \
    PYTHONUNBUFFERED=1 \
    "$malchan_python" -m uvicorn "malchan.app:create_app" --factory --host "$BIND_HOST" --port 8002
fi
start_frontend malchan-frontend 5174 "$MALCHAN/frontend" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=5174" "CHAN_BACKEND_PORT=8002" \
  "VITE_API_BASE=http://$PUBLIC_HOST:8002/api"

if ! cauchan_python=$(find_venv_python "$CAUCHAN" 2>/dev/null); then
  echo "[ERROR] cauchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use 8003; then
  echo "[RUNNING] cauchan-backend: port 8003 is already in use."
else
  start_bg cauchan-backend "$CAUCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=5175" "CHAN_BACKEND_PORT=8003" \
    "CAUCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:5175,http://localhost:5175" \
    PYTHONUNBUFFERED=1 \
    "$cauchan_python" -m uvicorn cauchan.api.app:app --app-dir "$CAUCHAN/src" --host "$BIND_HOST" --port 8003
fi
start_frontend cauchan-frontend 5175 "$CAUCHAN/web" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=5175" "CHAN_BACKEND_PORT=8003" \
  "VITE_API_BASE_URL=http://$PUBLIC_HOST:8003/api/v1"

if ! dchan_python=$(find_venv_python "$DCHAN" 2>/dev/null); then
  echo "[ERROR] dchan-backend: .venv Python not found. Run setup_all.sh first."
  FAILED=1
elif port_in_use 8004; then
  echo "[RUNNING] dchan-backend: port 8004 is already in use."
else
  start_bg dchan-backend "$DCHAN" env \
    "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
    "CHAN_FRONTEND_PORT=5176" "CHAN_BACKEND_PORT=8004" \
    "DCHAN_CORS_ORIGINS=http://$PUBLIC_HOST:5176,http://localhost:5176" \
    PYTHONUNBUFFERED=1 \
    "$dchan_python" -m uvicorn application.main:app --host "$BIND_HOST" --port 8004
fi
start_frontend dchan-frontend 5176 "$DCHAN/frontend" env \
  "$COMMON_PROFILE" "$COMMON_BIND" "$COMMON_PUBLIC" \
  "CHAN_FRONTEND_PORT=5176" "CHAN_BACKEND_PORT=8004" \
  "VITE_API_URL=http://$PUBLIC_HOST:8004"

echo
echo "Portal: http://$PUBLIC_HOST:5172"
echo "bochan: http://$PUBLIC_HOST:5173"
echo "malchan: http://$PUBLIC_HOST:5174"
echo "cauchan: http://$PUBLIC_HOST:5175"
echo "dchan: http://$PUBLIC_HOST:5176"
echo "Logs: $LOGS_DIR"

if [ "$FAILED" -ne 0 ]; then
  echo "[ERROR] One or more applications could not be launched."
  exit 1
fi

echo "[OK] Launch commands were issued for all applications."
