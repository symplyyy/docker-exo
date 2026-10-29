# Rapport d'incident — préprod Shop SAS

**Heure de début** : 14:53 · **Heure de résolution** : 14:57 · **Impact** : préprod indisponible

Fichiers corrigés : `solution/compose.yml`, `solution/nginx/default.conf`. Sorties dans `evidence/`.

## Chronologie du diagnostic

| Heure | Symptôme observé | Commande / preuve | Hypothèse | Résultat |
|-------|------------------|-------------------|-----------|----------|
| 14:53 | `docker compose up` refuse de démarrer | `docker compose config` → `can't set container_name and api as container name must be unique` | `container_name` + `replicas: 2` incompatibles | confirmé, `container_name` supprimé |
| 14:53 | front reste `Created` | `docker compose up` → `error mounting .../nginx to rootfs at /etc/nginx/conf.d/default.conf: not a directory` | on monte le dossier `nginx/` sur un fichier | confirmé, on monte `nginx/default.conf` |
| 14:54 | api-1 et api-2 `Exited (1)` | `docker compose logs api` → `Cannot find module '/app/server.js'` | `command: node server.js` mauvais chemin | confirmé, le fichier est `src/server.js`, je supprime `command` (le CMD de l'image est bon) |
| 14:54 | redis `Exited (1)` | `docker compose logs redis` → `bind: Address in use` sur 6379 | `network_mode: host` : redis prend le port de l'hôte (déjà utilisé) et n'est sur aucun réseau compose | confirmé, redis mis sur `backend` |
| 14:54 | logs db : `FATAL: role "postgres" does not exist` toutes les 5s | `docker compose logs db \| grep FATAL` | healthcheck `pg_isready -U postgres` alors que l'utilisateur est `shop` | confirmé, `-U shop -d shop` |
| 14:54 | api seulement sur `incident_public` | `docker inspect api --format '{{json .NetworkSettings.Networks}}'` | l'api ne peut pas joindre db/redis qui sont sur `backend` | confirmé, api ajoutée à `backend` |
| 14:54 | réseau public `internal` | `docker network inspect incident_public --format '{{.Internal}}'` → `true` | un réseau internal ne peut pas publier le port 8081 | confirmé, `internal` enlevé de `public` et mis sur `backend` |
| 14:54 | `DATABASE_URL` pointe vers `databse` | lecture du compose | faute de frappe, le DNS ne résoudrait pas | corrigé en `db` |
| 14:54 | `PORT: 8080` | lecture du compose + `ss -tln` dans l'api | nginx et le healthcheck de l'image attendent 3000 | `PORT: 3000` |
| 14:54 | `REDIS_URL` sans mot de passe | redis lancé avec `--requirepass r3dis` | l'API aurait `NOAUTH` | `redis://:r3dis@redis:6379` |
| 14:54 | `proxy_pass http://localhost:3000` | `default.conf` | dans le conteneur nginx, localhost = nginx lui-même | `proxy_pass http://api` (upstream `api:3000`) |
| 14:55 | `Bind for 127.0.0.1:8081 failed: port is already allocated` | `docker ps` | port pris par un autre conteneur sur mon poste (UI du registre du TP03) | arrêté, pas lié à la stack |
| 14:55 | nginx `host not found in upstream "api:3000"` | `docker inspect incident-front-1` → aucun réseau | le conteneur est resté sans réseau après l'échec du port | `docker compose up -d --force-recreate front` |
| 14:57 | tout `healthy`, `X-Cache: MISS` puis `HIT` | `docker compose ps`, `curl -i localhost:8081/products` x2 | | résolu |

## Anomalies trouvées

| # | Fichier / service | Anomalie | Correction | Catégorie |
|---|-------------------|----------|------------|----------|
| 1 | compose / api | `container_name: api` avec `replicas: 2` | supprimer `container_name` | config |
| 2 | compose / front | dossier `./nginx` monté sur le fichier `default.conf` | `./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro` | stockage |
| 3 | compose / api | `command: node server.js` (mauvais chemin) | supprimer, le CMD de l'image lance `src/server.js` | config |
| 4 | compose / api | `PORT: 8080` alors que nginx et le healthcheck utilisent 3000 | `PORT: 3000` | config |
| 5 | compose / api | `DATABASE_URL` avec `databse` | `db` | config |
| 6 | compose / api | api pas sur le réseau `backend` | `networks: [public, backend]` | réseau |
| 7 | compose / redis | `network_mode: host` : hors des réseaux compose, conflit de port | `networks: [backend]` | réseau |
| 8 | compose / api | `REDIS_URL` sans le mot de passe de `--requirepass` | `redis://:r3dis@redis:6379` | config / sécurité |
| 9 | compose / réseaux | `public` en `internal: true` (port 8081 impossible), `backend` ouvert | `public` normal, `backend` en `internal` | réseau / sécurité |
| 10 | compose / db | healthcheck `pg_isready -U postgres` (rôle inexistant) | `pg_isready -U shop -d shop` | config |
| 11 | nginx | `proxy_pass http://localhost:3000` | `upstream api { server api:3000; }` + `proxy_pass http://api` | réseau |
| 12 | compose / front | `depends_on: [api]` sans condition, pas de healthcheck front ni redis | healthchecks + `condition: service_healthy` | cycle de vie |
| 13 | compose | mots de passe en clair (`shop`, `r3dis`) | à passer en `secrets:` comme au TP04 | sécurité |

## Pourquoi ça n'a pas été détecté avant ?

Le compose n'a jamais été testé après la modification : pas de `docker compose config` (qui aurait vu l'erreur 1 tout de
suite), pas de healthcheck sur le front et redis, donc rien ne montrait que la stack était cassée. Pas de revue de code,
et le collègue est parti juste après.

## Actions de prévention

1. **CI** sur chaque modification du compose : `docker compose config -q` + un lint (dclint / hadolint pour les
   Dockerfile), puis `docker compose up -d --wait` et un smoke test (`curl /products` deux fois, vérifier `X-Cache: HIT`)
2. **healthchecks partout + `depends_on: condition: service_healthy`** et toujours `up --wait`, pour que la stack ne
   soit jamais considérée comme démarrée alors qu'un service est cassé
3. **revue de code obligatoire** (merge request) sur les fichiers d'infra, et pas de déploiement juste avant de partir en congé

## Partie 1 (rappels)

```
$ docker exec ctr-a ping -c1 ctr-b      (bridge par défaut)
ping: bad address 'ctr-b'
$ docker exec ctr-a ping -c1 ctr-b      (réseau utilisateur demo)
64 bytes from 192.168.16.3: seq=0 ttl=64 time=0.091 ms
$ docker exec ctr-a cat /etc/resolv.conf
nameserver 127.0.0.11
$ docker run --rm --network container:incident-api-1 nicolaka/netshoot ss -tln
LISTEN 0      511                *:3000             *:*
```
Sur le bridge par défaut il n'y a pas de DNS entre conteneurs, sur un réseau créé par l'utilisateur le DNS embarqué
(127.0.0.11) résout les noms. `--network container:X` partage la pile réseau de X : on voit ses ports sans rien
installer dans l'image.

Remarque : avec Docker 29, `docker run --name a` est refusé (nom trop court) et `docker rm -f a` interprète `a`
comme un début d'ID de conteneur, attention.

Bonus non faits.
