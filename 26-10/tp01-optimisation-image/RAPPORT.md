# TP01 - Rapport

Fichiers : `starter/shopapi/Dockerfile`, `starter/shopapi/.dockerignore`, `starter/shopapi/package-lock.json`
(récupéré dans l'image legacy pour pouvoir faire `npm ci`). L'ancien Dockerfile est gardé dans `Dockerfile.legacy`.

## Avant / après

| | legacy | 1.4.2 |
|---|---|---|
| Taille | 1.06GB | 177MB (124MB décompressée) |
| Couches | 9 | 8 |
| Rebuild après modif de `src/server.js` | `npm install` rejoué | 2.3s, `npm ci` en cache |
| Utilisateur | root | `uid=1000(node)` |
| `docker stop -t 10` | 10.15s, exit 137 (SIGKILL) | 0.28s, exit 0 |
| Healthcheck | aucun | `healthy` |
| Secrets / dump dans l'image | `.env`, `DATABASE_URL`, dump SQL | rien |
| CVE HIGH/CRITICAL (trivy) | - | 0 |
| hadolint | 5 warnings | rien |

## Choix

- multi-stage : `deps-dev` → `test` (`npm run lint` + `npm test`) → `deps-prod` (`npm ci --omit=dev`) → `runtime`
- l'image finale fait un `COPY --from=test`, sinon BuildKit ne lance pas l'étape test
- `.dockerignore` en liste blanche : seuls package.json, le lockfile, `src/` et `test/` passent
- cache mount sur `/root/.npm`
- runtime : alpine 3.23.7 + juste le binaire node copié depuis `node:20.20.2-alpine3.23`. Au début j'avais
  mis `FROM node:20-alpine` mais trivy trouvait 22 CVE dans le npm livré avec l'image (tar, glob, cross-spawn...)
  et 4 dans openssl. npm ne sert à rien à l'exécution donc je l'ai enlevé, et l'image fait 177MB au lieu de 212MB.
- node est le PID 1 (forme exec) donc il reçoit SIGTERM et le code de `server.js` ferme le serveur proprement.
  Avec `CMD npm start` c'est `sh` qui est PID 1, il ignore SIGTERM, donc Docker attend 10s puis envoie SIGKILL.
- labels OCI à la fin du Dockerfile pour que changer de version n'invalide pas le cache

## Vérifications

```
$ docker run --rm shopapi:1.4.2 id
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
$ docker run --rm shopapi:1.4.2 ls -a /app
.  ..  node_modules  package.json  src
$ docker inspect api --format '{{.State.Health.Status}}'
healthy
$ curl -s localhost:3000/products
[{"id":1,"name":"Clavier mécanique","price":89.9,"stock":12},...]
$ hadolint Dockerfile
$
```

Labels :
```json
{"org.opencontainers.image.revision":"77bed97","org.opencontainers.image.source":"https://gitlab.shop-sas.internal/platform/shopapi","org.opencontainers.image.version":"1.4.2", ...}
```

## Bonus

### B1 - distroless

`starter/shopapi/Dockerfile.distroless`, base `gcr.io/distroless/nodejs20-debian12:nonroot`.

- 199MB (plus gros que ma version alpine, 177MB), uid 65532, `healthy`, stop en 0.22s
- trivy : 7 CVE HIGH/CRITICAL dans les paquets debian 12, 0 dans node
- pas de shell : `docker exec apid sh` → `executable file not found`. Plus sûr mais pour debug il faut
  `docker debug`, l'image `:debug` de distroless ou un conteneur à côté (`--pid container:apid`)
- pas de `wget` pour le healthcheck, j'utilise node directement :
  `CMD ["/nodejs/bin/node", "-e", "require('http').get('http://127.0.0.1:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]`
- l'entrypoint est déjà `node`, donc `CMD ["src/server.js"]`

### B2 - --no-cache vs cache mount

Builder `shop` vidé au début (`evidence/bonus-b2-cache.txt`) :

| | temps |
|---|---|
| `--no-cache`, avec cache mount (1re fois) | 8.9s (pull des images de base) |
| `--no-cache`, avec cache mount (2e fois) | 2.7s |
| `--no-cache`, sans cache mount | 2.4s |
| package.json modifié, avec cache mount | 1.5s |
| package.json modifié, sans cache mount | 2.6s |

`--no-cache` ignore aussi le cache mount, donc avec `--no-cache` ça ne change rien. Le cache mount sert quand la couche
`npm ci` est invalidée (package.json modifié) : npm reprend les paquets dans `/root/.npm` au lieu de les retélécharger.
Ici les différences sont petites car il y a peu de dépendances.

### B3 - build reproductible

```bash
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) docker buildx build --builder shop --no-cache \
  -o type=oci,dest=img.tar,rewrite-timestamp=true .
```

| | build 1 | build 2 |
|---|---|---|
| sans `SOURCE_DATE_EPOCH` | acfdf4e6... | 7b9982ba... |
| avec `SOURCE_DATE_EPOCH` + `rewrite-timestamp=true` | e36ab76d... | e36ab76d... |

Ce qui empêche la reproductibilité : les dates (champ `created` de la config, mtime des fichiers dans les couches),
et les fichiers qui contiennent la date du build. Au début même avec `SOURCE_DATE_EPOCH` les digests étaient
différents : en comparant les couches j'ai trouvé `/var/log/apk.log` qui contient l'heure de l'`apk add`. Je le
supprime dans le même `RUN` et ça passe. Autres sources possibles : versions non épinglées (`apk add` sans version,
image sans digest, pas de lockfile), et l'attestation de provenance qui contient l'heure du build.
