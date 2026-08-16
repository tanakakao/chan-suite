#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOGS_DIR="$SUITE_ROOT/logs"
MARKER_VALUE=chan-suite-v1
STOP_TIMEOUT=${CHAN_STOP_TIMEOUT:-10}

case "$STOP_TIMEOUT" in
  ''|*[!0-9]*)
    echo "[ERROR] CHAN_STOP_TIMEOUT must be a non-negative integer."
    exit 1
    ;;
esac

if [ ! -d /proc ]; then
  echo "[ERROR] Safe managed shutdown currently requires Linux /proc."
  echo "No process was stopped."
  exit 1
fi

if [ ! -d "$LOGS_DIR" ]; then
  echo "CHAN SUITE STOP"
  echo
  echo "[OK] No logs directory exists; there are no managed PID records to stop."
  exit 0
fi

process_start_id() {
  pid=$1
  if [ ! -r "/proc/$pid/stat" ]; then
    return 1
  fi
  awk '{print $22}' "/proc/$pid/stat" 2>/dev/null
}

process_cwd() {
  pid=$1
  readlink "/proc/$pid/cwd" 2>/dev/null
}

collect_descendants() {
  parent=$1
  children=$(ps -eo pid=,ppid= 2>/dev/null | awk -v parent="$parent" '$2 == parent {print $1}')
  for child in $children; do
    collect_descendants "$child"
    printf '%s\n' "$child"
  done
}

any_alive() {
  for target in "$@"; do
    if kill -0 "$target" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

cleanup_metadata() {
  base=$1
  rm -f "$base.pid" "$base.cwd" "$base.start" "$base.managed"
}

stop_managed() {
  managed_file=$1
  base=${managed_file%.managed}
  name=${base##*/}
  pid_file="$base.pid"
  cwd_file="$base.cwd"
  start_file="$base.start"

  marker=$(cat "$managed_file" 2>/dev/null || true)
  if [ "$marker" != "$MARKER_VALUE" ]; then
    echo "[SKIP] $name: unrecognized managed-process marker."
    return 0
  fi
  if [ ! -f "$pid_file" ] || [ ! -f "$cwd_file" ] || [ ! -f "$start_file" ]; then
    echo "[SKIP] $name: incomplete managed-process metadata."
    return 0
  fi

  pid=$(cat "$pid_file" 2>/dev/null || true)
  case "$pid" in
    ''|*[!0-9]*)
      echo "[SKIP] $name: invalid PID record."
      return 0
      ;;
  esac

  if ! kill -0 "$pid" 2>/dev/null; then
    echo "[STALE] $name: PID $pid is no longer running."
    cleanup_metadata "$base"
    return 0
  fi

  expected_cwd=$(cat "$cwd_file" 2>/dev/null || true)
  expected_start=$(cat "$start_file" 2>/dev/null || true)
  current_cwd=$(process_cwd "$pid" || true)
  current_start=$(process_start_id "$pid" || true)

  case "$expected_cwd" in
    "$SUITE_ROOT"/apps/*) ;;
    *)
      echo "[SKIP] $name: recorded working directory is outside chan-suite/apps."
      return 0
      ;;
  esac

  if [ -z "$current_cwd" ] || [ "$current_cwd" != "$expected_cwd" ]; then
    echo "[SKIP] $name: PID $pid no longer belongs to the recorded application directory."
    return 0
  fi
  if [ -z "$expected_start" ] || [ -z "$current_start" ] || [ "$current_start" != "$expected_start" ]; then
    echo "[SKIP] $name: PID $pid was reused or its process identity cannot be verified."
    return 0
  fi

  descendants=$(collect_descendants "$pid")
  targets="$descendants $pid"
  echo "[STOP] $name: PID $pid"

  # All targets are numeric PIDs discovered from the verified managed root process.
  # shellcheck disable=SC2086
  kill -TERM $targets 2>/dev/null || true

  waited=0
  while [ "$waited" -lt "$STOP_TIMEOUT" ]; do
    # shellcheck disable=SC2086
    if ! any_alive $targets; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  # shellcheck disable=SC2086
  if any_alive $targets; then
    echo "[WARN] $name: forcing remaining managed process(es) to stop."
    # shellcheck disable=SC2086
    kill -KILL $targets 2>/dev/null || true
    sleep 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    echo "[ERROR] $name: PID $pid is still running."
    return 1
  fi

  cleanup_metadata "$base"
  echo "[STOPPED] $name"
  return 0
}

echo "CHAN SUITE STOP"
echo

found=0
failed=0
for managed_file in "$LOGS_DIR"/*.managed; do
  if [ ! -f "$managed_file" ]; then
    continue
  fi
  found=1
  if ! stop_managed "$managed_file"; then
    failed=1
  fi
done

if [ "$found" -eq 0 ]; then
  echo "[OK] No managed PID records were found."
  exit 0
fi

if [ "$failed" -ne 0 ]; then
  echo
  echo "[ERROR] One or more managed processes could not be stopped."
  exit 1
fi

echo
echo "[OK] Managed chan-suite processes are stopped."
