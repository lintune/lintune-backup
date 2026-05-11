#!/bin/bash
set -euo pipefail

# Find the Keycloak MariaDB container
MARIADB=$(docker ps --filter "name=keycloak" --format "{{.Names}}" \
    | grep -i mariadb | head -1)

if [[ -z "$MARIADB" ]]; then
    echo "keycloak mariadb container not found" >&2
    exit 1
fi

# $MYSQL_USER/$MYSQL_PASSWORD expand inside the container, not here
docker exec "$MARIADB" sh -c \
    'mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" --databases keycloak' \
    | gzip
