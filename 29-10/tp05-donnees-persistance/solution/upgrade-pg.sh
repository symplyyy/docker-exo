#!/usr/bin/env bash
set -euo pipefail

OLD=(docker compose -f compose.yml)
NEW=(docker compose -f compose.yml -f compose.pg16.yml)
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p backups

checksum() {
  "$@" exec -T db psql -U shop -d shop -tA -F ' ' -c \
    "SELECT count(*), md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders"
}

echo "== 1. checksum PG14"
"${OLD[@]}" up -d --wait db >/dev/null 2>&1
"${OLD[@]}" exec -T db psql -U shop -d shop -tAc "SHOW server_version"
BEFORE=$(checksum "${OLD[@]}"); echo "$BEFORE"

echo "== 2. dumps"
"${OLD[@]}" exec -T db pg_dumpall -U shop > "backups/all-$TS.sql"
"${OLD[@]}" exec -T db pg_dump -U shop -d shop -Fc > "backups/shop-$TS.dump"
ls -lh "backups/all-$TS.sql" "backups/shop-$TS.dump" | awk '{print $5, $NF}'

echo "== 3. arrêt PG14 (volume pgdata conservé)"
START=$(date +%s)
"${OLD[@]}" stop db >/dev/null 2>&1

echo "== 4. PG16 sur le volume pgdata16"
"${NEW[@]}" up -d --wait db >/dev/null 2>&1
"${NEW[@]}" exec -T db psql -U shop -d shop -tAc "SHOW server_version"

echo "== 5. restauration"
"${NEW[@]}" exec -T db pg_restore -U shop -d shop --no-owner < "backups/shop-$TS.dump"
echo "indisponibilité : $(( $(date +%s) - START ))s"

echo "== 6. checksum PG16"
AFTER=$(checksum "${NEW[@]}"); echo "$AFTER"

if [ "$BEFORE" = "$AFTER" ]; then
  echo "VERDICT : OK, migration sans perte"
else
  echo "VERDICT : ÉCHEC, retour arrière : docker compose -f compose.yml up -d --force-recreate db"
  exit 1
fi
