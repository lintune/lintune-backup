#!/bin/bash
set -euo pipefail

NC=$(docker ps --filter "name=nextcloud-aio-nextcloud" --format "{{.Names}}" | head -1)

if [[ -z "$NC" ]]; then
    echo "nextcloud-aio-nextcloud container not found" >&2
    exit 1
fi

# Always turn maintenance mode off on exit, even on failure
cleanup() {
    docker exec -u www-data "$NC" php /var/www/html/occ maintenance:mode --off \
        > /dev/null 2>&1 || true
}
trap cleanup EXIT

docker exec -u www-data "$NC" php /var/www/html/occ maintenance:mode --on \
    > /dev/null 2>&1

# Find the Nextcloud data volume on the host and stream it
DATA_SRC=$(docker inspect "$NC" \
    --format '{{range .Mounts}}{{if eq .Destination "/var/www/html/data"}}{{.Source}}{{end}}{{end}}')

if [[ -z "$DATA_SRC" ]]; then
    echo "could not locate nextcloud data volume" >&2
    exit 1
fi

tar czf - -C "$(dirname "$DATA_SRC")" "$(basename "$DATA_SRC")" 2>/dev/null
