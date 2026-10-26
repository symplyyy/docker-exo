# TP02 - Rapport

Machine : Mac M (arm64), Docker 29.0.1, builder `shop` en driver `docker-container`.
Registre : celui du TP03 (`localhost:5005` depuis le Mac, `registry.local:5000` dans le réseau Docker).
Les sorties des commandes sont dans `evidence/`.

## 1. La fuite

Le build échoue car `pypi.internal.example.com` n'existe pas. Pour voir la fuite je l'ai relancé avec les mêmes
identifiants mais vers `pypi.org` (qui les ignore). Le secret est visible :

1. dans `docker history --no-trunc` : `ARG PIP_INDEX_URL=https://svc-ci:Tr3sS3cret@...` et `RUN |1 PIP_INDEX_URL=...`
   (c'est dans la config de l'image, donc poussé au registre avec elle)
2. dans l'historique du build (`docker buildx history inspect`, onglet Builds de Docker Desktop) et dans les logs CI
3. dans une couche : `COPY . .` copie `pip.conf.example` qui contient le mot de passe

## 2. Secret mount

`RUN --mount=type=secret,id=pipconf,target=/etc/pip.conf pip install ...` avec un `pip.conf` local
(dans le `.gitignore` et exclu par le `.dockerignore`).

- `docker history worker:1.0 | grep -i secret` → rien
- `docker run --rm worker:1.0 cat /etc/pip.conf` → No such file or directory
- `docker save worker:1.0 | grep -a -c Tr3sS3cret` → 0
- utilisateur `uid=10001`, pas de pytest/ruff dans l'image finale, 237MB (contre 1.71GB)

Alternatives : `--mount=type=ssh` pour les dépendances git privées (on passe l'agent ssh, pas la clé),
et `--secret id=TOKEN,env=TOKEN` quand le secret est déjà une variable d'env en CI.

## 3. Cache mount

| | avec cache mount | sans |
|---|---|---|
| build à froid | 11.5s | 10.9s |
| rebuild sans changement | 0.5s | |
| après prune des couches + ajout de `requests` | 8.3s, 16 paquets depuis le cache, 10 téléchargés | 11.3s, 26 téléchargés |
| `--no-cache` | 5.9s, 26 téléchargés | |

J'ai fait le prune sur le builder `shop` uniquement (`docker buildx prune --builder shop --filter type=regular`)
pour ne pas vider le cache de mes autres projets.

- cache de couches : résultat d'une instruction. Si `requirements.txt` change, la couche est invalidée et pip repart de zéro.
- cache mount : un dossier du builder monté pendant le `RUN`, pas dans l'image. pip rejoue mais ne retélécharge que ce qui manque.
- `--no-cache` : ignore les couches et aussi le cache mount (26 téléchargés), mais ne le supprime pas : le build
  d'après réutilise bien les 16 paquets.

## 4. Multi-arch

| build | temps |
|---|---|
| arm64 seul | 10.9s |
| amd64 seul | 10.5s |
| amd64 + arm64 → archive OCI | 15.3s |

- `--push` ou `-o` est obligatoire car le résultat est un index avec plusieurs images, et le store classique
  de Docker ne garde qu'une image par tag. Sans sortie : `No output specified with docker-container driver`.
  (Avec Docker 29 et le store containerd, `--load` avec 2 plateformes marche quand même.)
- le manifest list contient une entrée par plateforme (digest, taille, `os`/`architecture`) + les attestations en `unknown/unknown`.
  Le client prend celle qui correspond à sa machine. Voir `evidence/04-imagetools-inspect.txt`.
- `TARGETARCH` : `ARG TARGETARCH` puis `--mount=type=cache,id=pip-${TARGETARCH},...` → deux caches `pip-amd64` et `pip-arm64`.
- arm64 sur une machine amd64 passe par QEMU qui émule chaque instruction, c'est beaucoup plus lent (surtout s'il faut compiler).
  Ici amd64 n'est pas plus lent car Docker Desktop utilise Rosetta et il n'y a rien à compiler. Alternative :
  un builder avec un nœud natif par archi (`docker buildx create --append --platform linux/arm64 ...`) ou la cross-compilation.

## 5. Cache distant

Chaque runner = builder supprimé puis recréé.

| | mode=max | mode=min |
|---|---|---|
| runner A, build + `--cache-to` | 19.8s | 16.5s |
| runner B, `--cache-from`, rien n'a changé | 4.0s | 4.0s |
| runner C, sans cache | 15.6s | 16.7s |
| runner neuf après modif de `worker/main.py` | 6.6s | 24.5s |
| taille du cache | 142MB | 102MB |

`mode=min` n'exporte que les couches de l'image finale, `mode=max` exporte aussi les étapes intermédiaires
(builder, test). Dès que le code change l'étape test est rejouée, donc avec min il faut réinstaller les dépendances de dev.
En CI on peut aussi utiliser `type=gha` (GitHub Actions) ou `type=s3`.

## 6. Bake

`starter/docker-bake.hcl` : variables `REGISTRY`, `VERSION`, `GIT_SHA`, cible `_common` (plateformes, labels,
attestations), cibles `api` et `worker` dans le groupe `default`, et `worker-test` qui ne fait que l'étape test.

- `docker buildx bake --print` → OK
- `bake worker-test` → 19.5s, tests OK sur amd64 et arm64
- `bake --set '*.platform=linux/arm64' --load` → 16.3s
- `bake --push` → 13.8s

Problème rencontré : `attest = []` dans `worker-test` ne remplace pas la valeur héritée, j'ai dû mettre `disabled=true`.

## Bonus

- B1 : `--network=none` ne marche pas directement, pip a besoin de l'index même avec le cache. J'ai fait une variante
  (`B1-Dockerfile.offline`) qui télécharge les wheels dans un cache mount puis installe avec `--no-index --find-links`.
  Après un build en ligne, le build sans réseau passe. Utile pour les environnements sans internet (air-gapped).
- B2 : provenance + SBOM activés dans le bake. La provenance contient les build-args et le digest de l'image de base
  (pas le secret), le SBOM liste 106 paquets par archi.
- B3 : `B3-Dockerfile.uv`, on copie le binaire depuis `ghcr.io/astral-sh/uv` et on fait `uv pip install`, cache mount sur
  `/root/.cache/uv`. uv ne lit pas `pip.conf` donc le secret est passé en variable d'env :
  `--mount=type=secret,id=uvindex,env=UV_INDEX_URL` et `docker build --secret id=uvindex,env=UV_INDEX_URL`
  (il faut `dockerfile:1.10`). Le secret n'apparaît pas dans l'historique.

  | | pip | uv |
  |---|---|---|
  | cache vide : total / install prod / install dev | 10.1s / 1.2s / 1.8s | 6.9s / 0.4s / 0.9s |
  | couches purgées, cache plein | 8.8s / 0.8s / 1.1s | 6.0s / 0.1s / 0.1s |
