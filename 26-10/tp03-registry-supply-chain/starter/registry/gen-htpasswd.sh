#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
HTPASSWD=(docker run --rm --entrypoint htpasswd httpd:2.4.65-alpine)
{
  "${HTPASSWD[@]}" -B -C 10 -bn ci  "${CI_PASSWORD:-ci-push-2024}"
  "${HTPASSWD[@]}" -B -C 10 -bn dev "${DEV_PASSWORD:-dev-pull-2024}"
} | grep -v '^$' > auth/htpasswd
cut -d: -f1,2 auth/htpasswd | cut -c1-20
