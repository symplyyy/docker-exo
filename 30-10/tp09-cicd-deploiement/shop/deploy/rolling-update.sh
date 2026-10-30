#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${VERSION:?VERSION à définir (ex: VERSION=sha-abc1234)}"
export VERSION
COMPOSE=(docker compose -f compose.yml -f compose.prod.yml ${COMPOSE_EXTRA:-})
SERVICE="${SERVICE:-api}"
TIMEOUT="${TIMEOUT:-60}"

wait_healthy() {
  local id=$1 t=0
  until [ "$(docker inspect -f '{{.State.Health.Status}}' "$id")" = healthy ]; do
    sleep 1; t=$((t + 1))
    if [ "$t" -ge "$TIMEOUT" ]; then echo "$id pas healthy après ${TIMEOUT}s" >&2; return 1; fi
  done
}

start=$(date +%s)
"${COMPOSE[@]}" pull -q "$SERVICE"
old=$("${COMPOSE[@]}" ps -q "$SERVICE")
n=$(echo "$old" | grep -c .)
[ "$n" -ge 2 ] || echo "attention : seulement $n réplica(s), il y aura une coupure" >&2
echo "$SERVICE : $n réplica(s) -> image $VERSION"

for id in $old; do
  before=$("${COMPOSE[@]}" ps -q "$SERVICE")
  "${COMPOSE[@]}" up -d --no-deps --no-recreate --scale "$SERVICE=$(( $(echo "$before" | grep -c .) + 1 ))" "$SERVICE" >/dev/null 2>&1
  new=$(comm -13 <(echo "$before" | sort) <("${COMPOSE[@]}" ps -q "$SERVICE" | sort))
  echo "  nouveau $(docker inspect -f '{{.Name}}' $new | tr -d /) ($(docker inspect -f '{{.Config.Image}}' $new))"
  wait_healthy "$new"
  sleep 6
  echo "  arrêt de $(docker inspect -f '{{.Name}}' $id | tr -d /)"
  docker stop -t 15 "$id" >/dev/null
  docker rm "$id" >/dev/null
done

echo "terminé en $(( $(date +%s) - start ))s"
"${COMPOSE[@]}" ps "$SERVICE" --format '  {{.Name}}  {{.Image}}  {{.Status}}'
