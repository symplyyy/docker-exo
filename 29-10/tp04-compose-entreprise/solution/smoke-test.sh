#!/usr/bin/env bash
set -uo pipefail

BASE="${BASE:-http://api.localhost}"
COMPOSE="${COMPOSE:-docker compose}"
FAIL=0

check() {
  if [ "$1" = "$2" ]; then echo "OK   $3"; else echo "FAIL $3 (attendu: $2, obtenu: $1)"; FAIL=1; fi
}

check "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/ready")" 200 "/ready"

curl -s -o /dev/null "$BASE/products"
cache=$(curl -s -D - -o /dev/null "$BASE/products" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-cache"{print $2}')
check "$cache" HIT "/products en cache (X-Cache)"

qty=$((RANDOM % 5 + 1))
code=$(curl -s -o /tmp/order.json -w '%{http_code}' -X POST "$BASE/orders" -H 'Content-Type: application/json' -d "{\"productId\":1,\"quantity\":$qty}")
check "$code" 201 "POST /orders"

status=""
for _ in $(seq 1 10); do
  status=$($COMPOSE exec -T db psql -U shop -d shop -tAc "SELECT status FROM orders ORDER BY id DESC LIMIT 1")
  [ "$status" = "confirmed" ] && break
  sleep 1
done
check "$status" confirmed "commande traitée par le worker"

rm -f /tmp/order.json
exit $FAIL
