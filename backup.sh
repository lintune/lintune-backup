#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHARED="${SHARED_VOL:-/backups}"
STORAGE="${BACKUP_STORAGE_PATH:-/storage}"
KEY="${BACKUP_PRIVATE_KEY_PATH:-/backups/id_backup}"
DATE="$(date +%Y%m%d_%H%M%S)"
SERVERS_JSON="$SHARED/servers.json"

ext_for() {
    case "$1" in
        keycloak) echo "sql.gz" ;;
        *)        echo "tar.gz" ;;
    esac
}

if [[ ! -f "$SERVERS_JSON" ]]; then
    echo "[backup] No servers.json, nothing to do."
    exit 0
fi

mkdir -p "$STORAGE"

result="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"servers\":{}}"

while IFS= read -r server; do
    server_id=$(echo "$server" | jq -r '.id')
    label=$(echo "$server"    | jq -r '.label')
    host=$(echo "$server"     | jq -r '.internal_host')
    user=$(echo "$server"     | jq -r '.ssh_user')
    port=$(echo "$server"     | jq -r '.ssh_port')

    result=$(echo "$result" | jq \
        --arg id "$server_id" --arg lbl "$label" \
        '.servers[$id] = {"label": $lbl, "services": {}}')

    while IFS= read -r service; do
        ext="$(ext_for "$service")"
        outfile="$STORAGE/${service}-${server_id}-${DATE}.${ext}"
        tmpfile="${outfile}.tmp"

        echo "[backup] $label → $service"
        errfile="${outfile}.err"

        if ssh -i "$KEY" \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               -o ConnectTimeout=30 \
               -p "$port" \
               "${user}@${host}" \
               'bash -s' < "$SCRIPT_DIR/scripts/backup-${service}.sh" \
               > "$tmpfile" 2>"$errfile"; then

            rm -f "$errfile"
            mv "$tmpfile" "$outfile"
            size_bytes=$(stat -c%s "$outfile")
            size_mb=$(( size_bytes / 1048576 ))
            fname="$(basename "$outfile")"
            result=$(echo "$result" | jq \
                --arg id "$server_id" --arg svc "$service" \
                --argjson mb "$size_mb" --arg f "$fname" \
                '.servers[$id].services[$svc] = {"ok": true, "size_mb": $mb, "file": $f}')
            echo "[backup] $label → $service OK (${size_mb}MB)"
        else
            ssh_err=$(cat "$errfile" 2>/dev/null | head -5 | tr '\n' ' ' | sed 's/[[:space:]]*$//')
            rm -f "$tmpfile" "$errfile"
            echo "[backup] $label → $service FAILED: ${ssh_err:-no error output}"
            result=$(echo "$result" | jq \
                --arg id "$server_id" --arg svc "$service" \
                --arg err "${ssh_err:-backup failed}" \
                '.servers[$id].services[$svc] = {"ok": false, "error": $err}')
        fi

    done < <(echo "$server" | jq -r '.services[]')

done < <(jq -c '.[]' "$SERVERS_JSON")

echo "$result" > "$SHARED/last_backup.json"
echo "[backup] done"
