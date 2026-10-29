#!/usr/bin/env bash
N="${1:-1000}"
URL="${URL:-http://api.localhost}"
for i in $(seq 1 "$N"); do
  curl -s -o /dev/null "$URL/products" &
  if (( i % 10 == 0 )); then
    curl -s -o /dev/null -X POST "$URL/orders" -H 'Content-Type: application/json' -d '{"productId":1,"quantity":2}' &
    curl -s -o /dev/null "$URL/nope" &
    wait
  fi
done
wait
echo "$N requêtes envoyées"
