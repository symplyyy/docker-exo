#!/usr/bin/env bash
set -euo pipefail

DB_USER="${DB_USER:-shop}"
DB_NAME="${DB_NAME:-shop}"
KEEP="${KEEP:-7}"
BACKUP_DIR="${BACKUP_DIR:-$PWD/backups}"
PROJECT=$(docker compose config --format json | jq -r .name)
VOLUME="${VOLUME:-${PROJECT}_pgdata}"
TS=$(date +%Y%m%d-%H%M%S)

mkdir -p "$BACKUP_DIR"

docker compose exec -T db pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$BACKUP_DIR/$DB_NAME-$TS.dump"
echo "dump logique : $BACKUP_DIR/$DB_NAME-$TS.dump ($(du -h "$BACKUP_DIR/$DB_NAME-$TS.dump" | cut -f1))"

if [ "${RAW:-0}" = "1" ]; then
  docker compose stop db >/dev/null
  docker run --rm -v "$VOLUME":/data:ro -v "$BACKUP_DIR":/backup alpine:3.20 \
    tar czf "/backup/$VOLUME-$TS.tar.gz" -C /data .
  docker compose start db >/dev/null
  echo "sauvegarde brute : $BACKUP_DIR/$VOLUME-$TS.tar.gz ($(du -h "$BACKUP_DIR/$VOLUME-$TS.tar.gz" | cut -f1))"
fi

ls -1t "$BACKUP_DIR"/*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | xargs rm -f
ls -1t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs rm -f
echo "$(ls "$BACKUP_DIR"/*.dump | wc -l | tr -d ' ') dump(s) gardé(s)"
