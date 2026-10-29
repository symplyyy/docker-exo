# TP04 - Rapport

Tout est dans `solution/` : `compose.yml`, `compose.override.yml`, `compose.prod.yml`, `.env.example`, `Makefile`,
`smoke-test.sh`, `db/init.sql`, `db/migrations/002-add-sku.sql`. Les apps viennent du TP01 (shopapi) et du TP02 (shop-worker).

Avant de lancer : `openssl rand -hex 16 > secrets/db_password.txt` et `cp .env.example .env`
(+ `apps/shop-worker/pip.conf` du TP02 pour builder le worker).

## 1. Problèmes du docker-compose.yml de départ

1. `version: '3'` : obsolète, ignoré par Compose v2 (warning)
2. `links` : obsolète, les services se trouvent déjà par leur nom sur le réseau
3. images pas épinglées (`postgres`, `redis` = latest) : une mise à jour peut tout casser du jour au lendemain
4. postgres et redis publiés sur l'hôte (5432, 6379) : accessibles depuis l'extérieur, redis sans mot de passe
5. mot de passe `postgres` en clair dans le fichier, répété 3 fois (db, api, worker)
6. utilisateur `postgres` superuser utilisé par l'application
7. `sleep 10` pour attendre la base : soit trop court (crash), soit du temps perdu, aucune garantie
8. un seul réseau par défaut : le proxy/l'API et la base sont sur le même réseau, pas de séparation
9. aucun healthcheck : `up` rend la main alors que rien n'est prêt
10. pas de volumes nommés : les données de postgres sont dans un volume anonyme, perdu facilement
11. `restart` incohérent : seulement `always` sur le worker, rien sur les autres
12. pas de limites CPU/mémoire, pas de rotation des logs (json-file qui grossit à l'infini)
13. pas de reverse proxy, l'API est exposée directement sur 3000
14. pas de nom de projet : il dépend du nom du dossier
15. `command: sh -c ...` : `sh` est le PID 1, SIGTERM n'arrive pas à node

## 2. compose.yml

- `name: shop`, réseaux `front` et `back` (`internal: true`)
- images épinglées, healthchecks partout avec l'ancre `x-healthcheck-defaults`, `depends_on` en `service_healthy`
- logs : ancre `x-logging` (json-file, 10m x 3), `restart: unless-stopped`
- mot de passe dans `secrets/db_password.txt` (gitignored), `POSTGRES_PASSWORD_FILE` pour la base
- pour l'API et le worker, qui ne lisent que `DATABASE_URL`, je construis l'URL au démarrage sans toucher au code :

```yaml
entrypoint: ["/bin/sh", "-c"]
command:
  - >-
    export DATABASE_URL="postgres://shop:$$(cat /run/secrets/db_password)@db:5432/shop" &&
    exec node src/server.js
```
  le `exec` remplace `sh` par node, qui reste PID 1 et reçoit bien SIGTERM. Le `$$` évite que compose interpole.
- Traefik : `api.localhost` → API, healthcheck du backend sur `/health`
- profils `tools` (adminer sur `adminer.localhost`) et `ops` (`migrate`)

J'ai dû passer Traefik en **v3.6.2** au lieu de v3.1 : avec Docker 29 la v3.1 n'arrive pas à parler au daemon
(`Provider error ... Error response from daemon`, l'API Docker minimale est passée en 1.44).

```
$ docker compose -f compose.yml up -d --wait && docker compose ps
api       Up (healthy)   3000/tcp
db        Up (healthy)   5432/tcp
redis     Up (healthy)   6379/tcp
traefik   Up (healthy)   0.0.0.0:80->80/tcp
worker    Up (healthy)   9100/tcp
$ curl api.localhost/ready
{"status":"ready","checks":{"db":"ok","redis":"ok"}}
$ MIGRATION=002-add-sku.sql docker compose run --rm migrate
ALTER TABLE
UPDATE 3
```

La base n'a aucun port publié, redis n'a pas internet (`wget: bad address`), traefik ne résout pas `db`.

## 3. Dev (compose.override.yml)

Bind mount de `apps/shopapi/src`, `node --watch`, `LOG_LEVEL=debug`, ports 3000, 5434 (postgres), 8088 (dashboard).
J'ai pris 5434 et 8088 car 5432 et 8080 sont déjà utilisés sur ma machine.
Un conteneur seulement sur un réseau `internal` ne peut pas publier de port, donc en dev la base est aussi sur `front`.

Reload :
```
api-1  | Restarting 'src/server.js'
api-1  | {"level":30,...,"msg":"shopapi démarré"}
$ curl localhost:3000/health
{"status":"ok","reload":true}
```

## 4. Prod (compose.prod.yml)

- `build: !reset null` pour supprimer le build hérité, images `${REGISTRY}/shopapi:${VERSION}` du registre du TP03
- 2 réplicas de l'API, limites CPU/mémoire, `read_only` + `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges`
- pas de port de debug ni de dashboard (fichier override pas chargé quand on passe `-f`)

Répartition de charge (logs d'accès traefik après 6 `curl`) :
```
   3 http://172.28.0.3:3000
   3 http://172.28.0.4:3000
```

`up -d --scale api=3` → 3 réplicas. Puis `up -d` → retour à 2 : compose réapplique `deploy.replicas` du fichier,
le `--scale` n'est pas mémorisé.

Variable obligatoire : `REGISTRY= docker compose -f compose.yml -f compose.prod.yml config` →
`required variable REGISTRY is missing a value: REGISTRY doit être défini`.

## 5. Makefile

`make up`, `make down`, `make tools`, `make prod-up`, `make prod-down`, `make migrate M=002-add-sku.sql`, `make test`.

```
$ make test
OK   /ready
OK   /products en cache (X-Cache)
OK   POST /orders
OK   commande traitée par le worker
```

## Bonus

B3 : oui, adminer est joignable via Traefik même si `back` est `internal`, parce qu'il est sur les deux réseaux :
Traefik lui parle par `front`, et adminer parle à la base par `back`. `internal` empêche seulement de sortir vers l'extérieur.
B4 : fait dans `compose.prod.yml` (voir plus haut). Les autres bonus ne sont pas faits.
