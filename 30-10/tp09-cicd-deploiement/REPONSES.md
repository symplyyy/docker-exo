# TP09 - Réponses

Dépôt : `shop/` (TP04 + `compose.hardened.yml`/`audit.sh` du TP08 + `release-gate.sh`/`tools.sh` du TP03).
Je ne l'ai pas initialisé comme dépôt git séparé, il est dans mon dépôt de TP.
Workflow : `shop/.github/workflows/ci.yml` (validé avec actionlint, pas exécuté sur GitHub). Simulation locale : `shop/ci-local.sh pr|main|tag vX.Y.Z`.
Sorties dans `evidence/`.

## Pipeline

| Événement | Étapes | Preuve |
|---|---|---|
| PR | hadolint, `compose config`, build `test`, build multi-arch sans push | `evidence/ci-pr.txt` |
| main | + push `sha-<sha>` (provenance + sbom, cache registre), trivy bloquant, signature, vérification, rolling update préprod | `evidence/ci-main.txt` |
| tag `v*` | + tags `1.5.0` / `1.5` (crane, sans rebuild), approbation manuelle, vérification de signature, rolling update prod | `evidence/ci-tag.txt` |

En local la signature se fait avec une clé (`ci/cosign.key`, gitignored), dans le workflow GitHub c'est du keyless
(OIDC, `id-token: write`) et la vérification se fait sur l'identité du workflow. L'approbation manuelle est
l'`environment: production` (reviewers obligatoires configurés dans GitHub), simulée par un `read` dans `ci-local.sh`.

Signature : `evidence/signature.txt` (`shopapi:1.5.0` vérifiée ; `1.4.2` signée avec la clé du TP03 → refusée).

## Déploiement distant

Pas de serveur SSH sur ma machine (Remote Login désactivé), j'ai créé les contextes `preprod` et `prod` vers le socket
Docker local. Avec un vrai serveur : `docker context create preprod --docker "host=ssh://deploy@preprod.local"`.

Prérequis côté serveur :
- Docker installé, utilisateur `deploy` dans le groupe `docker` (équivalent root, compte dédié, pas de mot de passe)
- clé SSH publique de la CI dans `~deploy/.ssh/authorized_keys`, clé privée en secret CI (`DEPLOY_SSH_KEY`)
- accès au registre (`docker login` une fois avec un compte en lecture seule)
- `.env` et `secrets/db_password.txt` **déjà présents sur le serveur**, créés une fois à la main par un admin ou par un
  outil (Ansible + Vault, gestionnaire de secrets). Ils ne passent jamais par git ni par la CI. Avec un contexte Docker
  SSH, compose lit `secrets:` et `.env` sur la machine qui lance la commande, donc en pratique on lance compose sur le
  serveur (ou on y synchronise le dossier de la stack), ou on utilise des secrets externes (Swarm, Vault)

## Zéro interruption

Mesure : `deploy/measure-downtime.sh` (100 req/s sur `/health`, timeout 2s).

| Déploiement | Requêtes | Échecs |
|---|---|---|
| naïf `up -d --force-recreate api` | 4000 | **519** (19 × 502, 500 × 404, ~5s de coupure) |
| `rolling-update.sh` (version finale) | 5000 | **1** (502) |
| rollback `VERSION=1.4.2 ./deploy/rolling-update.sh` | 5000 | **1** (502) |

Ce que j'ai dû régler pour passer de ~40 à 1 échec : retry Traefik (5 tentatives), `dialtimeout=500ms` (sinon une
requête envoyée vers un conteneur qui vient de s'arrêter reste bloquée jusqu'au timeout), `providersThrottleDuration=500ms`
(Traefik voit plus vite les changements), pas de connexions persistantes vers les backends (`maxidleconnsperhost=-1`).
Il reste une 502 par déploiement que je n'ai pas réussi à éliminer : une requête en cours sur le réplica arrêté au mauvais moment.

Rôle de chaque brique et ce qui se passe sans :

| Brique | Rôle | Sans |
|---|---|---|
| `HEALTHCHECK` de l'image | Docker sait quand l'API répond vraiment | le conteneur est « up » dès le démarrage du process, avant que l'app soit prête |
| `start_period` | laisse le temps de démarrer sans compter les échecs | un démarrage lent est vu comme unhealthy |
| Traefik + healthcheck | Traefik n'envoie du trafic qu'aux conteneurs healthy | il route vers un réplica pas encore prêt → 502 |
| `--wait` / attente healthy dans le script | on n'arrête l'ancien que quand le nouveau est prêt | on coupe l'ancien alors que le nouveau ne répond pas encore |
| réplicas ≥ 2 | il y a toujours un réplica qui répond | avec 1 seul, pendant le remplacement il n'y a plus personne |
| SIGTERM géré (TP01) + `stop -t 15` / `stop_grace_period` | l'API finit les requêtes en cours avant de sortir | SIGKILL immédiat (ou au bout de 10s) → requêtes coupées |
| proxy (Traefik) | point d'entrée stable, répartit entre les réplicas | les clients parlent directement à un conteneur qui disparaît |

## Rollback

`VERSION=1.4.2 ./deploy/rolling-update.sh` : **26s**, 1 échec sur 5000 (`evidence/rollback.txt`).

C'est possible parce que :
- les tags sont immuables (`sha-<sha>`, semver) : l'ancienne version existe toujours dans le registre, identique
- l'image est encore sur le serveur (pas de pull, ou pull rapide)
- la base est compatible avec l'ancienne version (le schéma n'a pas changé)

Migration non rétro-compatible (ex. renommer une colonne) : l'ancienne version ne marche plus avec le nouveau schéma,
le rollback de l'image ne suffit pas. Il faut faire les migrations en plusieurs étapes (expand/contract) : d'abord
ajouter la nouvelle colonne en gardant l'ancienne, déployer le code qui gère les deux, migrer les données, et seulement
dans une release suivante supprimer l'ancienne colonne. Sinon il faut une sauvegarde et un script de retour du schéma.

Bonus non faits.
