#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
EVENT="${1:-pr}"
GIT_TAG="${2:-}"
SHA=$(git rev-parse --short HEAD)
REGISTRY="${REGISTRY:-localhost:5005}"
REG_INTERNAL="${REG_INTERNAL:-registry.local:5000}"
BUILDER="${BUILDER:-shop}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
TAG="sha-$SHA"
TRIVY_SERVER="${TRIVY_SERVER-http://trivy-server:4954}"
TRIVY_TOKEN="${TRIVY_TOKEN:-shop-scan-2024}"

step() { printf '\n==> %s\n' "$*"; }

[ -f secrets/db_password.txt ] || openssl rand -hex 16 > secrets/db_password.txt
[ -f .env ] || cp .env.example .env
[ -f apps/shop-worker/pip.conf ] || printf '[global]\nindex-url = https://pypi.org/simple\n' > apps/shop-worker/pip.conf

step "lint : hadolint"
for d in apps/shopapi apps/shop-worker; do
  docker run --rm -i hadolint/hadolint:v2.12.0 < "$d/Dockerfile" && echo "  $d/Dockerfile OK"
done

step "lint : docker compose config"
docker compose -f compose.yml config -q && echo "  compose.yml OK"
REGISTRY=$REGISTRY VERSION=$TAG docker compose -f compose.yml -f compose.prod.yml config -q && echo "  compose.prod.yml OK"

step "tests : build de l'étape test"
docker buildx build --builder "$BUILDER" --target test -o type=cacheonly apps/shopapi -q >/dev/null && echo "  shopapi : tests OK"
docker buildx build --builder "$BUILDER" --target test -o type=cacheonly --secret id=pipconf,src=apps/shop-worker/pip.conf apps/shop-worker -q >/dev/null && echo "  shop-worker : tests OK"

if [ "$EVENT" = pr ]; then
  step "build des images (sans push)"
  for app in shopapi shop-worker; do
    docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" -o type=cacheonly \
      --secret id=pipconf,src=apps/shop-worker/pip.conf apps/$app -q >/dev/null && echo "  $app OK"
  done
  echo; echo "PIPELINE PR : OK"
  exit 0
fi

step "build multi-arch + push $TAG (provenance + sbom)"
for app in shopapi shop-worker; do
  docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" \
    --secret id=pipconf,src=apps/shop-worker/pip.conf \
    --build-arg APP_VERSION="$TAG" --build-arg VERSION="$TAG" --build-arg GIT_SHA="$SHA" \
    --label org.opencontainers.image.revision="$SHA" \
    --provenance=mode=max --sbom=true \
    --cache-from type=registry,ref=$REGISTRY/cache:$app \
    --cache-to type=registry,ref=$REGISTRY/cache:$app,mode=max \
    -t "$REGISTRY/$app:$TAG" --push apps/$app -q >/dev/null
  echo "  $REGISTRY/$app:$TAG"
done

step "scan trivy (bloquant : HIGH/CRITICAL corrigeables)"
for app in shopapi shop-worker; do
  ./tools.sh trivy image --quiet ${TRIVY_SERVER:+--server $TRIVY_SERVER --token $TRIVY_TOKEN} --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
    --format table "$REG_INTERNAL/$app:$TAG" </dev/null | grep -E 'Total|^│' | head -5 || { echo "  $app : SCAN KO"; exit 1; }
  echo "  $app : 0 vulnérabilité bloquante"
done

step "signature cosign"
for app in shopapi shop-worker; do
  digest=$(./tools.sh crane digest "$REG_INTERNAL/$app:$TAG" </dev/null)
  ./tools.sh cosign sign --key ci/cosign.key --tlog-upload=false "$REG_INTERNAL/$app@$digest" </dev/null >/dev/null 2>&1
  echo "  $app@${digest:0:19}... signé"
done

verify() {
  for app in shopapi shop-worker; do
    ./tools.sh cosign verify --key ci/cosign.pub --insecure-ignore-tlog=true "$REG_INTERNAL/$app:$1" </dev/null >/dev/null 2>&1 \
      && echo "  $app:$1 signature vérifiée" || { echo "  $app:$1 SIGNATURE INVALIDE"; exit 1; }
  done
}

if [ "$EVENT" = main ]; then
  step "déploiement préprod (contexte docker preprod)"
  verify "$TAG"
  DOCKER_CONTEXT=preprod VERSION=$TAG ./deploy/rolling-update.sh
  DOCKER_CONTEXT=preprod VERSION=$TAG WORKER_VERSION=$TAG docker compose -f compose.yml -f compose.prod.yml up -d --no-deps --wait worker 2>/dev/null | tail -1
  echo; echo "PIPELINE MAIN : OK ($TAG déployé en préprod)"
  exit 0
fi

if [ "$EVENT" = tag ]; then
  [[ "$GIT_TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || { echo "usage: ci-local.sh tag v1.2.3"; exit 1; }
  semver="${GIT_TAG#v}"; minor="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
  step "tags semver $semver / $minor"
  for app in shopapi shop-worker; do
    ./tools.sh crane tag "$REG_INTERNAL/$app:$TAG" "$semver" </dev/null 2>/dev/null
    ./tools.sh crane tag "$REG_INTERNAL/$app:$TAG" "$minor" </dev/null 2>/dev/null
    echo "  $app:$semver, $app:$minor"
  done
  step "déploiement prod : approbation manuelle"
  if [ "${AUTO_APPROVE:-}" != yes ]; then
    read -r -p "  déployer $semver en prod ? [y/N] " answer
    [ "$answer" = y ] || { echo "  refusé"; exit 1; }
  fi
  verify "$semver"
  DOCKER_CONTEXT=prod VERSION=$semver ./deploy/rolling-update.sh
  DOCKER_CONTEXT=prod VERSION=$semver WORKER_VERSION=$semver docker compose -f compose.yml -f compose.prod.yml up -d --no-deps --wait worker 2>/dev/null | tail -1
  echo; echo "PIPELINE TAG : OK ($semver en prod)"
fi
