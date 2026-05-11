#!/bin/bash
set -euo pipefail

SHARED="${SHARED_VOL:-/backups}"
KEY="${BACKUP_PRIVATE_KEY_PATH:-/backups/id_backup}"
DEFAULT_CRON="${BACKUP_CRON:-0 2 * * *}"

# Fix key permissions if it exists
if [[ -f "$KEY" ]]; then
    chmod 600 "$KEY"
fi

# Ensure storage dir exists
mkdir -p "${BACKUP_STORAGE_PATH:-/storage}"

# Resolve cron schedule: file > env var > hardcoded default
CRON_FILE="$SHARED/backup_cron"
if [[ -f "$CRON_FILE" ]]; then
    SCHEDULE="$(cat "$CRON_FILE")"
    rm -f "$CRON_FILE"
else
    SCHEDULE="$DEFAULT_CRON"
fi

# Write crontab
echo "$SCHEDULE /app/backup.sh >> /proc/1/fd/1 2>&1" > /etc/crontabs/root

# Start cron daemon
crond -f &
CROND_PID=$!
echo "[lintune-backup] crond started (schedule: $SCHEDULE)"

# Hand off to watcher — it runs forever and is PID 1's main child
exec /app/watcher.sh
