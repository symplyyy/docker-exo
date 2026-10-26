#!/usr/bin/env bash
set -euo pipefail
REG_DIR="$(cd "$(dirname "$0")/../../../tp03-registry-supply-chain/starter/registry" && pwd)"
CFG="$(mktemp -d)"; trap 'rm -rf "$CFG"' EXIT
printf '{"auths":{"registry.local:5000":{"auth":"%s"}}}' "$(printf '%s' "${REG_USER:-dev}:${REG_PASSWORD:-dev-pull-2024}" | base64)" > "$CFG/config.json"
docker run --rm --network shop-registry \
  -v "$REG_DIR/certs/ca.crt:/usr/local/share/ca-certificates/shop-ca.crt:ro" \
  -v "$CFG/config.json:/root/.docker/config.json:ro" \
  docker:29.0.1-cli sh -c 'update-ca-certificates >/dev/null 2>&1; docker buildx imagetools "$@"' -- "$@"
