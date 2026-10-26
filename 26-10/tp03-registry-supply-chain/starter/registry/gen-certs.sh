#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/certs"
DAYS_CA=3650 DAYS_SRV=397

if [[ ! -f ca.key ]]; then
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -key ca.key -sha256 -days "$DAYS_CA" -out ca.crt \
    -subj "/O=Shop SAS/CN=Shop SAS Internal Root CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
fi

openssl genrsa -out registry.key 2048
openssl req -new -key registry.key -out registry.csr -subj "/O=Shop SAS/CN=registry.local"
openssl x509 -req -in registry.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out registry.crt -days "$DAYS_SRV" -sha256 -extfile <(cat <<EXT
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:registry.local,DNS:localhost,IP:127.0.0.1
EXT
)
rm -f registry.csr
chmod 600 ./*.key
openssl x509 -in registry.crt -noout -subject -issuer -ext subjectAltName
