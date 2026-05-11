#!/bin/bash
set -euo pipefail

MAILCOW_DIR="/opt/mailcow-dockerized"
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

if [[ ! -d "$MAILCOW_DIR" ]]; then
    echo "mailcow directory not found at $MAILCOW_DIR" >&2
    exit 1
fi

cd "$MAILCOW_DIR"
MAILCOW_BACKUP_LOCATION="$TMPDIR" bash helper-scripts/backup_and_restore.sh backup all \
    > /dev/null 2>&1

tar czf - -C "$TMPDIR" .
