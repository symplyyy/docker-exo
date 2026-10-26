#!/usr/bin/env bash
set -euo pipefail

REPO="${1:?usage: retention.sh REPO [N] [--dry-run]}"
KEEP="${2:-5}"
DRY_RUN=false
[[ "${3:-}" == "--dry-run" || "${2:-}" == "--dry-run" ]] && DRY_RUN=true
[[ "$KEEP" == "--dry-run" ]] && KEEP=5

H=registry.local
P="${REGISTRY_PORT:-5005}"
U="https://$H:$P/v2"
CA_CERT="${CA_CERT:-$(dirname "$0")/starter/registry/certs/ca.crt}"
SEMVER='^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'

api() { curl -fsS --resolve "$H:$P:127.0.0.1" --cacert "$CA_CERT" -u "${REG_USER:-ci}:${REG_PASSWORD:-ci-push-2024}" "$@"; }

digest_of() {
  api -I -H "Accept: $ACCEPT" "$U/$REPO/manifests/$1" | tr -d '\r' \
    | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'
}

created_of() {
  local manifest config
  manifest=$(api -H "Accept: $ACCEPT" "$U/$REPO/manifests/$1")
  if jq -e '.manifests' >/dev/null <<<"$manifest"; then
    local child
    child=$(jq -r '[.manifests[] | select(.platform.os != "unknown")][0].digest' <<<"$manifest")
    manifest=$(api -H "Accept: $ACCEPT" "$U/$REPO/manifests/$child")
  fi
  config=$(jq -r '.config.digest' <<<"$manifest")
  api "$U/$REPO/blobs/$config" | jq -r '.created // "1970-01-01T00:00:00Z"'
}

TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
TAGS=$(api "$U/$REPO/tags/list" | jq -r '.tags // [] | .[]')
[[ -z "$TAGS" ]] && { echo "$REPO : aucun tag"; exit 0; }

for tag in $TAGS; do
  kind=other; [[ "$tag" =~ $SEMVER ]] && kind=semver
  created="-"; [[ $kind == other ]] && created=$(created_of "$tag")
  echo "$created $tag $(digest_of "$tag") $kind" >> "$TMP"
done
NB_TAGS=$(wc -l < "$TMP" | tr -d ' ')

PROTECTED=" "
while read -r _ tag d _; do
  PROTECTED+="$d "; echo "  garde   $tag (semver)"
done < <(awk '$4=="semver"' "$TMP")

i=0; TO_DELETE=""
while read -r created tag d _; do
  if (( i < KEEP )); then
    PROTECTED+="$d "; echo "  garde   $tag ($created, parmi les $KEEP plus récents)"
  else
    TO_DELETE+="$tag:$d "
  fi
  i=$((i + 1))
done < <(awk '$4=="other"' "$TMP" | sort -r)

deleted=0
for item in $TO_DELETE; do
  tag="${item%%:sha256*}"; d="${item#"$tag":}"
  if [[ "$PROTECTED" == *" $d "* ]]; then
    echo "  ignore  $tag : son digest ${d:7:12} est partagé avec un tag conservé"
    continue
  fi
  if $DRY_RUN; then
    echo "  [dry-run] supprimerait $tag (${d:7:12})"
  else
    api -X DELETE -o /dev/null "$U/$REPO/manifests/$d" || true
    echo "  supprimé $tag (${d:7:12})"
  fi
  PROTECTED+="$d "
  deleted=$((deleted + 1))
done

echo "$REPO : $NB_TAGS tags, $deleted supprimé(s)$($DRY_RUN && echo ' (dry-run)')."
(( deleted > 0 )) && ! $DRY_RUN && echo "Libérer l'espace : docker compose exec registry registry garbage-collect /etc/docker/registry/config.yml   (jamais --delete-untagged avec registry:2 : il supprime les manifestes enfants des images multi-arch)"
exit 0
