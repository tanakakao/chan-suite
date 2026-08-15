#!/usr/bin/env sh

set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SUITE_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
APPS_DIR="$SUITE_ROOT/apps"
GITHUB_OWNER=${CHAN_GITHUB_OWNER:-tanakakao}

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git was not found on PATH." >&2
    exit 1
fi

if ! mkdir -p "$APPS_DIR"; then
    echo "[ERROR] Failed to create $APPS_DIR." >&2
    exit 1
fi

failed=0

for repo in chan-portal bochan malchan cauchan dchan; do
    target="$APPS_DIR/$repo"
    remote="https://github.com/$GITHUB_OWNER/$repo.git"

    if [ -d "$target/.git" ]; then
        echo "[SKIP] $repo already exists."
        continue
    fi

    if [ -e "$target" ]; then
        echo "[ERROR] $target exists but is not a Git repository." >&2
        failed=1
        continue
    fi

    echo "[CLONE] $remote"
    if git clone "$remote" "$target"; then
        echo "[OK] $repo"
    else
        echo "[ERROR] Failed to clone $repo." >&2
        failed=1
    fi
done

if [ "$failed" -ne 0 ]; then
    echo "[ERROR] One or more repositories could not be cloned." >&2
    exit 1
fi

echo "[OK] chan-suite repositories are ready under $APPS_DIR."
