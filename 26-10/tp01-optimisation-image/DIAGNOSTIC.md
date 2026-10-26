# TP01 - Diagnostic de l'image shopapi:legacy

Les sorties complètes sont dans `evidence/`.

## Taille / performance

| # | Problème | Preuve | Impact |
|---|---|---|---|
| 1 | Image énorme | `docker image ls shopapi:legacy` → 1.06GB | registre saturé, pulls lents |
| 2 | Base `ubuntu:22.04` + node installé à la main | `docker history` : apt-get nodejs 173MB | image lourde, version de node pas maîtrisée |
| 3 | Outils de build inutiles en prod | `docker history` : curl wget vim git build-essential python3 = 379MB, `which gcc git vim` les trouve | taille + surface d'attaque |
| 4 | Cache apt pas nettoyé, `apt-get update` dans une couche séparée | couche `apt-get update` 80.7MB, dive : /var/lib/dpkg, /var/log/apt gaspillés | poids inutile, couche update qui peut être périmée |
| 5 | `COPY . /app` avant `npm install` | modifier `src/server.js` relance `npm install` (voir étape 2) | toute la CI réinstalle les dépendances à chaque commit |
| 6 | Dépendances de dev dans l'image | `ls node_modules` → eslint, nodemon ; `npm install -g nodemon` | taille + paquets inutiles en prod |
| 7 | Cache npm dans l'image | dive : `/root/.npm/_cacache/...` | poids inutile |
| 8 | Pas de `.dockerignore`, pas de lockfile | `ls -la /app` → Dockerfile, .gitignore, dump-prod-2024.sql, .env | build pas reproductible, contexte inutile |

## Sécurité

| # | Problème | Preuve | Impact |
|---|---|---|---|
| 9 | Conteneur en root | `docker run --rm shopapi:legacy id` → `uid=0(root)` | une faille dans l'app = root dans le conteneur |
| 10 | Secret dans `ENV` | `env \| grep -i database` → `DATABASE_URL=postgres://shop:S3cret!@db.internal...` ; visible aussi dans `docker history` | mot de passe de la base lisible par toute personne qui peut pull |
| 11 | `.env` copié dans l'image | `cat /app/.env` → `AWS_SECRET_ACCESS_KEY=...`, trivy le détecte en CRITICAL | fuite de clés AWS |
| 12 | Dump de prod dans l'image | `ls -la /app` → `dump-prod-2024.sql` | fuite de données |
| 13 | `NODE_ENV=development` | `env` | stack traces affichées, perfs moins bonnes |
| 14 | Image de base non épinglée, script `curl \| bash` | Dockerfile, hadolint DL4006 / DL3008 / DL3016 | build non reproductible, risque supply chain |

## Exploitabilité

| # | Problème | Preuve | Impact |
|---|---|---|---|
| 15 | `CMD npm start` en forme shell | `docker exec api-legacy ps` → PID 1 = `/bin/sh -c npm start`, puis npm, puis sh, puis node | SIGTERM n'arrive pas à node |
| 16 | Arrêt non propre | `time docker stop -t 10` → 10.15s, ExitCode=137, pas de log "arrêt demandé" | rolling updates lentes, connexions coupées net |
| 17 | Pas de HEALTHCHECK | `docker inspect` → `Healthcheck=null` | l'orchestrateur ne sait pas si l'API répond |
| 18 | Pas de labels OCI | seul label : `org.opencontainers.image.version=22.04` (celui d'ubuntu) | on ne sait pas quelle version / quel commit tourne |
| 19 | hadolint | 5 warnings (DL3008 x2, DL4006, DL3016, DL3025) + infos | non conforme au standard 7 |

Remarque : sur mon Docker Desktop le stop timeout par défaut est de 1s, donc il faut faire `docker stop -t 10` pour voir les 10s.

## Étape 2 - invalidation du cache

```
COPY . /app      <- change dès qu'un fichier du repo change
RUN npm install  <- donc rejoué à chaque fois
```

Le cache d'une instruction dépend du contenu des fichiers copiés avant. Comme on copie tout le repo
avant `npm install`, n'importe quel changement (code, README) invalide la couche et toutes celles d'après.

Ordre idéal des couches (de la moins souvent modifiée à la plus souvent modifiée) :

1. image de base épinglée
2. paquets système
3. `package.json` + `package-lock.json`
4. `npm ci`
5. code source (`src/`)
6. métadonnées (labels avec version / commit)
