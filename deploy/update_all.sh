#!/usr/bin/env sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APPS_DIR="$SUITE_ROOT/apps"
FAILED=0

if ! command -v git >/dev/null 2>&1; then
  echo "[ERROR] git was not found on PATH."
  exit 1
fi

for repo in chan-portal bochan malchan cauchan dchan; do
  repo_dir="$APPS_DIR/$repo"
  if [ ! -d "$repo_dir" ]; then
    echo "[SKIP] $repo: directory not found."
    continue
  fi
  if [ ! -d "$repo_dir/.git" ]; then
    echo "[ERROR] $repo: directory exists but is not a Git repository."
    FAILED=1
    continue
  fi
  if [ -n "$(git -C "$repo_dir" status --porcelain)" ]; then
    echo "[SKIP] $repo: working tree has local changes. Commit or stash them first."
    FAILED=1
    continue
  fi
  if ! git -C "$repo_dir" symbolic-ref --quiet --short HEAD >/dev/null 2>&1; then
    echo "[SKIP] $repo: detached HEAD. Check out a branch first."
    FAILED=1
    continue
  fi
  echo "[UPDATE] $repo"
  if git -C "$repo_dir" pull --ff-only; then
    echo "[OK] $repo"
  else
    echo "[ERROR] $repo: git pull --ff-only failed."
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "[ERROR] One or more repositories could not be updated."
  exit 1
fi

echo "[OK] All cloned repositories are up to date."
