#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CA="$HERE/starter/registry/certs/ca.crt"
TOOL="${1:?usage: tools.sh crane|cosign|syft|trivy ARGS...}"; shift

case "$TOOL" in
  crane)  IMAGE=gcr.io/go-containerregistry/crane@sha256:5ccb3ca884e3890d820fbf5ce4071fa3bb89469a72cc3f0ac7404a99c2a68788 ;;
  cosign) IMAGE=ghcr.io/sigstore/cosign/cosign:v2.6.1 ;;
  syft)   IMAGE=anchore/syft:v1.33.0 ;;
  trivy)  IMAGE=aquasec/trivy:0.67.2 ;;
  *) echo "outil inconnu : $TOOL" >&2; exit 2 ;;
esac

AUTH="$(mktemp -d)"; trap 'rm -rf "$AUTH"' EXIT
printf '{"auths":{"registry.local:5000":{"auth":"%s"}}}' \
  "$(printf '%s' "${REG_USER:-ci}:${REG_PASSWORD:-ci-push-2024}" | base64)" > "$AUTH/config.json"

docker run --rm -i --network shop-registry \
  -v "$CA:/certs/shop-ca.crt:ro" -e SSL_CERT_DIR=/etc/ssl/certs:/certs \
  -v "$AUTH:/auth:ro" -e DOCKER_CONFIG=/auth \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v trivy-cache:/root/.cache/trivy \
  -v "$PWD:/work" -w /work \
  -e COSIGN_PASSWORD="${COSIGN_PASSWORD-}" -e COSIGN_YES=true \
  "$IMAGE" "$@"
