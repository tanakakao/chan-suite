#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
PROFILE=${1:-Local}
SERVER_HOST=${2:-${CHAN_SERVER_HOST:-}}

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
    echo "Usage: $0 [Local|Intranet] [server-host]"
    exit 1
    ;;
esac

if command -v python3 >/dev/null 2>&1; then
  HOST_PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  HOST_PYTHON=python
else
  echo "[ERROR] Python was not found on PATH."
  exit 1
fi

port_in_use() {
  "$HOST_PYTHON" -c 'import socket,sys; s=socket.socket(); s.settimeout(0.2); code=s.connect_ex(("127.0.0.1", int(sys.argv[1]))); s.close(); raise SystemExit(0 if code == 0 else 1)' "$1" >/dev/null 2>&1
}

echo "CHAN SUITE STATUS"
echo
echo "Profile    : $PROFILE"
echo "Bind host  : $BIND_HOST"
echo "Public host: $PUBLIC_HOST"
echo

"$HOST_PYTHON" - "$SUITE_ROOT/config/apps.json" <<'PY' | while IFS='|' read -r name path enabled frontend backend; do
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    applications = json.load(stream)["applications"]

for app in applications:
    frontend = "" if app.get("frontendPort") is None else str(int(app["frontendPort"]))
    backend = "" if app.get("backendPort") is None else str(int(app["backendPort"]))
    enabled = "true" if app.get("enabled") is True else "false"
    print(f"{app['name']}|{app['path']}|{enabled}|{frontend}|{backend}")
PY
  echo "$name"
  app_dir="$SUITE_ROOT/$path"
  if [ ! -d "$app_dir" ]; then
    echo "  directory : NOT FOUND"
    echo
    continue
  fi

  echo "  directory : OK"
  if [ -n "$frontend" ]; then
    if port_in_use "$frontend"; then
      state=RUNNING
    else
      state=STOPPED
    fi
    echo "  frontend  : $frontend $state"
    echo "  frontend url : http://$PUBLIC_HOST:$frontend"
  fi

  if [ -n "$backend" ]; then
    if port_in_use "$backend"; then
      state=RUNNING
    else
      state=STOPPED
    fi
    echo "  backend   : $backend $state"
    echo "  backend url : http://$PUBLIC_HOST:$backend"
  fi

  if [ "$enabled" != "true" ]; then
    echo "  enabled   : false"
  fi
  echo
done
