#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REF="${1:?usage: verified-run.sh registry.local:5000/IMAGE:TAG [args docker run...]}"; shift

digest=$("$HERE/tools.sh" crane digest "$REF" </dev/null 2>/dev/null) || { echo "image introuvable : $REF"; exit 1; }
repo="${REF%:*}"

if ! (cd "$HERE" && ./tools.sh cosign verify --key cosign.pub --insecure-ignore-tlog=true "$repo@$digest" </dev/null >/dev/null 2>&1); then
  echo "REFUSÉ : $REF ($digest) n'est pas signée par cosign.pub"
  exit 1
fi
echo "signature OK : $repo@$digest"

local_ref="localhost:5005/${repo#*/}@$digest"
exec docker run "$@" "$local_ref"
