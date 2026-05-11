#!/bin/bash
set -euo pipefail

# Find the Keycloak MariaDB container
MARIADB=$(docker ps --filter "name=keycloak" --format "{{.Names}}" \
    | grep -i mariadb | head -1)

if [[ -z "$MARIADB" ]]; then
    echo "keycloak mariadb container not found" >&2
    exit 1
fi

# $MYSQL_ROOT_PASSWORD expands inside the container, not here
docker exec "$MARIADB" sh -c \
    'mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" --databases keycloak 2>/dev/null' \
    | gzip
