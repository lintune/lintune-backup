#!/bin/bash

SHARED="${SHARED_VOL:-/backups}"

echo "[watcher] started, polling every 30s"

while true; do
    # Trigger immediate backup
    if [[ -f "$SHARED/backup_now" ]]; then
        rm -f "$SHARED/backup_now"
        echo "[watcher] backup_now triggered"
        /app/backup.sh >> /proc/1/fd/1 2>&1 &
    fi

    # Update cron schedule
    if [[ -f "$SHARED/backup_cron" ]]; then
        SCHEDULE="$(cat "$SHARED/backup_cron")"
        rm -f "$SHARED/backup_cron"
        echo "$SCHEDULE /app/backup.sh >> /proc/1/fd/1 2>&1" > /etc/crontabs/root
        pkill -HUP crond 2>/dev/null || true
        echo "[watcher] cron schedule updated to: $SCHEDULE"
    fi

    sleep 30
done
