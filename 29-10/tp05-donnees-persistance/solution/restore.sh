#!/usr/bin/env bash
set -euo pipefail

FILE="${1:?usage: restore.sh FICHIER.dump}"
DB_USER="${DB_USER:-shop}"
DB_NAME="${DB_NAME:-shop}"

docker compose up -d --wait db >/dev/null
docker compose exec -T db pg_restore -U "$DB_USER" -d "$DB_NAME" --clean --if-exists --no-owner < "$FILE"
echo "restauré : $FILE"
