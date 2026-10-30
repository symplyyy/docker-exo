#!/usr/bin/env bash
set -uo pipefail

IMAGE="${1:?usage: release-gate.sh IMAGE [--push REGISTRY_IMAGE]}"
PUSH_TO=""
[[ "${2:-}" == "--push" ]] && PUSH_TO="${3:?--push REGISTRY_IMAGE}"

TOOLS="$(cd "$(dirname "$0")" && pwd)/tools.sh"
FAIL=0

ok()  { echo "  [OK]   $*"; }
ko()  { echo "  [FAIL] $*"; FAIL=1; }

echo "== release gate : $IMAGE"

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image introuvable"; exit 1
fi

for l in version revision source; do
  v=$(docker image inspect "$IMAGE" --format "{{index .Config.Labels \"org.opencontainers.image.$l\"}}")
  [[ -n "$v" ]] && ok "label $l = $v" || ko "label org.opencontainers.image.$l absent"
done

user=$(docker image inspect "$IMAGE" --format '{{.Config.User}}')
if [[ -z "$user" || "$user" == "root" || "$user" == "0" || "$user" == 0:* ]]; then
  ko "utilisateur root"
else
  ok "utilisateur $user"
fi

hc=$(docker image inspect "$IMAGE" --format '{{if .Config.Healthcheck}}{{json .Config.Healthcheck.Test}}{{end}}')
[[ -n "$hc" ]] && ok "healthcheck $hc" || ko "pas de HEALTHCHECK"

if "$TOOLS" trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --format json "$IMAGE" </dev/null >/tmp/gate-vuln.json 2>/dev/null; then
  ok "aucune CVE HIGH/CRITICAL corrigeable"
else
  n=$(jq '[.Results[]?.Vulnerabilities[]?] | length' /tmp/gate-vuln.json 2>/dev/null || echo "?")
  ko "$n CVE HIGH/CRITICAL corrigeables"
fi

if "$TOOLS" trivy image --quiet --scanners secret --exit-code 1 --format json "$IMAGE" </dev/null >/tmp/gate-secret.json 2>/dev/null; then
  ok "aucun secret détecté"
else
  ko "secret(s) : $(jq -r '[.Results[]? | select(.Secrets) | .Target] | join(", ")' /tmp/gate-secret.json 2>/dev/null)"
fi
rm -f /tmp/gate-vuln.json /tmp/gate-secret.json

if (( FAIL )); then
  echo "== REFUSÉ"
  exit 1
fi
echo "== ACCEPTÉ"

[[ -z "$PUSH_TO" ]] && exit 0

host_ref="localhost:5005/${PUSH_TO#*/}"
docker tag "$IMAGE" "$host_ref" && docker push -q "$host_ref" >/dev/null || exit 1
digest=$("$TOOLS" crane digest "$PUSH_TO" </dev/null) || exit 1
echo "push : $PUSH_TO@$digest"

cd "$(dirname "$TOOLS")"
"$TOOLS" syft "registry:$PUSH_TO@$digest" -q -o spdx-json=sbom-gate.json </dev/null || exit 1
COSIGN_PASSWORD="${COSIGN_PASSWORD-}" "$TOOLS" cosign sign --key ci/cosign.key --tlog-upload=false "${PUSH_TO%:*}@$digest" </dev/null >/dev/null 2>&1 || exit 1
COSIGN_PASSWORD="${COSIGN_PASSWORD-}" "$TOOLS" cosign attest --key ci/cosign.key --tlog-upload=false --type spdxjson --predicate sbom-gate.json "${PUSH_TO%:*}@$digest" </dev/null >/dev/null 2>&1 || exit 1
rm -f sbom-gate.json
echo "signé + SBOM attesté"
