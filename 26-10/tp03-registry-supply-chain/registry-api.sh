#!/usr/bin/env bash
set -euo pipefail
REG_DIR="$(cd "$(dirname "$0")/starter/registry" && pwd)"
H=registry.local P=${REGISTRY_PORT:-5005}; U=https://$H:$P/v2
ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json'
api(){ curl -fsS --resolve "$H:$P:127.0.0.1" --cacert "$REG_DIR/certs/ca.crt" -u "${REG_USER:-ci}:${REG_PASSWORD:-ci-push-2024}" "$@"; }
digest(){ api -I -H "Accept: $ACCEPT" "$U/$1/manifests/$2" | tr -d '\r' | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}'; }

echo '### Dépôts : GET /v2/_catalog'; api "$U/_catalog" | jq -c .
echo '### Tags de shopapi : GET /v2/shopapi/tags/list'; api "$U/shopapi/tags/list" | jq -c .
echo '### Digest de shopapi:1.0 : HEAD /v2/shopapi/manifests/1.0 (Accept: index OCI + manifest list + manifest v2)'
D=$(digest shopapi 1.0); echo "Docker-Content-Digest: $D"
echo "### Même HEAD sans en-tête Accept (le registre suppose un vieux client schema1) :"
curl -sS -o /dev/null -w '   HTTP %{http_code}\n' -I --resolve "$H:$P:127.0.0.1" --cacert "$REG_DIR/certs/ca.crt" -u "${REG_USER:-ci}:${REG_PASSWORD:-ci-push-2024}" "$U/shopapi/manifests/1.0"
echo "### Tags pointant sur $D :"
for t in $(api "$U/shopapi/tags/list" | jq -r '.tags[]'); do [[ "$(digest shopapi "$t")" == "$D" ]] && echo "   shopapi:$t"; done
echo "### DELETE /v2/shopapi/manifests/$D"
api -X DELETE -o /dev/null -w 'HTTP %{http_code}\n' "$U/shopapi/manifests/$D"
echo '### Tags après suppression :'; api "$U/shopapi/tags/list" | jq -c .
