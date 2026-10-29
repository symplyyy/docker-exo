#!/usr/bin/env bash
docker compose exec -T db psql -U shop -d shop -tA -F ' ' -c \
  "SELECT count(*), md5(string_agg(id::text || status, ',' ORDER BY id)) FROM orders"
