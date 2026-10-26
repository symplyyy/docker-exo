#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")"
H=registry.local; P=${REGISTRY_PORT:-5005}; U=https://$H:$P
C=(curl -s --resolve "$H:$P:127.0.0.1" --cacert certs/ca.crt)
code(){ "${C[@]}" -o /dev/null -w 'HTTP %{http_code}\n' "$@"; }

echo '$ curl https://registry.local/v2/  (sans identifiants)';      code "$U/v2/"
echo '$ curl sans --cacert (CA inconnue du système)';               curl -s -o /dev/null --resolve "$H:$P:127.0.0.1" "$U/v2/"; echo "   exit $? (60 = certificat non approuvé)"
echo '$ curl -u dev:mauvais /v2/';                                    code -u dev:mauvais "$U/v2/"
echo '$ curl -u dev:dev-pull-2024 /v2/_catalog';                      "${C[@]}" -u dev:dev-pull-2024 "$U/v2/_catalog"
echo '$ TLS négocié';                                                 "${C[@]}" -v -o /dev/null -u dev:dev-pull-2024 "$U/v2/" 2>&1 | grep -E 'SSL connection|subjectAltName|issuer:|Docker-Distribution' | sed 's/^[*<] */   /'
echo
echo '$ RBAC : dev tente un push (POST /blobs/uploads/)';            "${C[@]}" -w ' HTTP %{http_code}\n' -u dev:dev-pull-2024 -X POST "$U/v2/shopapi/blobs/uploads/"
echo '$ RBAC : dev tente une suppression';                            "${C[@]}" -w ' HTTP %{http_code}\n' -u dev:dev-pull-2024 -X DELETE "$U/v2/shopapi/manifests/sha256:$(printf '0%.0s' {1..64})"
echo '$ RBAC : dev se fait passer pour ci (avec son mot de passe)';  code -u ci:dev-pull-2024 -X POST "$U/v2/shopapi/blobs/uploads/"
echo '$ ci peut ouvrir un upload';                                    code -u ci:ci-push-2024 -X POST "$U/v2/shopapi/blobs/uploads/"
echo '$ dev peut lire les tags';                                      "${C[@]}" -u dev:dev-pull-2024 "$U/v2/shopapi/tags/list"; echo
