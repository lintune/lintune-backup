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

# Stream data volume from inside the container (avoids host /var/lib/docker/ permission issues)
docker exec "$NC" tar czf - /mnt/ncdata
