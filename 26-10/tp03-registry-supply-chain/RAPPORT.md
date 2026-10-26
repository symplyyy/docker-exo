# TP03 - Rapport

Sorties des commandes dans `evidence/`.

## 1. Registre

`starter/registry/` :
- `gen-certs.sh` : CA interne + certificat avec SAN `registry.local`, `localhost`, `127.0.0.1`
- `gen-htpasswd.sh` : comptes `ci` et `dev` en bcrypt
- `compose.yml` : `registry` (config dans `config/registry.yml`, volume nommé, delete activé, healthcheck),
  `gateway` nginx (TLS), `mirror` Docker Hub sur 5001, `ui` (joxit) sur 8081, tout en `restart: unless-stopped`
- `validate.sh` : les tests ci-dessous

Différences avec l'énoncé :
- le port 5000 est pris par AirPlay sur Mac, donc le registre est publié sur 5005. Dans le réseau Docker il reste `registry.local:5000`.
- htpasswd ne fait pas la différence entre push et pull : les deux comptes peuvent tout faire. J'ai mis nginx devant
  pour que `dev` ne puisse faire que des GET/HEAD. Le mot de passe est toujours vérifié par le registre.
- je n'ai pas modifié `/etc/hosts` ni le `daemon.json` de Docker Desktop, j'ai utilisé `curl --resolve` et
  `docker pull localhost:5001/library/alpine:3.20` pour tester le mirror.

Résultats :
```
curl /v2/ sans identifiants              -> 401
curl sans --cacert                        -> exit 60 (certificat non approuvé)
curl -u dev:dev-pull-2024 /v2/_catalog    -> {"repositories":["shopapi"]}
dev fait un POST (push)                   -> 403
dev se fait passer pour ci                -> 401
ci fait un POST                           -> 202
docker login localhost:5005 -u ci         -> Login Succeeded
docker push localhost:5005/shopapi:1.4.2  -> OK
docker compose down / up                  -> le tag est toujours là
mirror : 1er pull 3.8s, 2e pull 1.7s, library/alpine dans le cache du mirror
```

**htpasswd suffit-il ?** Non. Pas de droits par dépôt, pas de groupes, pas de SSO/LDAP, mots de passe dans un fichier,
pas d'audit. Harbor / Nexus / Artifactory / ECR / ACR / GAR ajoutent : RBAC par projet, SSO, scan de vulnérabilités
intégré, tags immuables, quotas, réplication entre sites, rétention automatique, signatures.

## 2. API

`registry-api.sh` (curl + jq) : catalogue, tags, digest avec `HEAD` + bon `Accept`, suppression par digest.

- sans en-tête `Accept`, le registre répond 404 pour une image multi-arch (il essaie de renvoyer l'ancien format schema1)
- `shopapi:1.0` et `shopapi:77bed97` pointaient sur le même manifeste : un seul `DELETE` par digest a supprimé les deux tags
- `registry garbage-collect` : 343.8M → 320.1M

**Problème** : j'ai d'abord fait le GC avec `--delete-untagged`, ça a supprimé les manifestes enfants des images
multi-arch (`crane tag` donnait `MANIFEST_BLOB_UNKNOWN`). C'est un bug connu de registry 2.x. J'ai repoussé les images
et maintenant je fais le GC sans cette option (vérifié : les images restent complètes).

`retention.sh REPO N [--dry-run]` garde les N tags non-semver les plus récents (date `created` de la config) et ne
touche jamais aux tags semver. Si un tag à supprimer a le même digest qu'un tag gardé, il est ignoré, sinon le
`DELETE` supprimerait aussi le tag gardé. Test sur un dépôt `demo` : `main-02` à `main-04` supprimés, `main-01` ignoré
car même digest que `1.0.0`.

## 3. Tags

Voir `TAGGING.md`.

## 4. SBOM, scan, signature

Outils lancés en conteneur avec `tools.sh` (crane, cosign, syft, trivy).

- `syft` → `sbom.json`, 340 paquets (320 npm, 18 apk)
- `trivy --severity HIGH,CRITICAL --ignore-unfixed` sur la première version de `shopapi:1.4.2` : 26 CVE, 22 dans le
  npm fourni avec l'image node (pas dans l'app) et 4 dans openssl. J'ai changé le Dockerfile du TP01 (alpine 3.23.7 +
  binaire node seul) → 0 CVE
- `trivy --scanners secret shopapi:legacy` → trouve la clé AWS dans `/app/.env` (CRITICAL)
- `cosign generate-key-pair`, `cosign sign`, `cosign verify` OK, `cosign attest` avec le SBOM OK
  (`--tlog-upload=false` car registre privé sans Rekor)

Dans le registre la signature crée des tags `sha256-<digest>.sig` et `sha256-<digest>.att` dans le même dépôt.

**La signature suit le digest, pas le tag.** Quand j'ai repoussé une nouvelle image sous `1.4.2`,
`cosign verify shopapi:1.4.2` a donné `no signatures found` : l'ancienne signature est toujours là mais attachée
à l'ancien digest. Il a fallu re-signer.

## 5. Porte de release

`starter/release-gate.sh IMAGE [--push REGISTRY_IMAGE]` vérifie : labels version/revision/source, utilisateur non root,
HEALTHCHECK, CVE HIGH/CRITICAL corrigeables, secrets. Si tout passe et qu'on donne `--push` : push, SBOM, signature, attestation.

```
$ ./starter/release-gate.sh shopapi:legacy
  [FAIL] label org.opencontainers.image.revision absent
  [FAIL] label org.opencontainers.image.source absent
  [FAIL] utilisateur root
  [FAIL] pas de HEALTHCHECK
  [FAIL] secret(s) : /app/.env
== REFUSÉ   (exit 1)

$ ./starter/release-gate.sh shopapi:1.4.2 --push registry.local:5000/shopapi:1.4.2
  [OK] ... (7 contrôles)
== ACCEPTÉ
push : registry.local:5000/shopapi:1.4.2@sha256:0bb45158...
signé + SBOM attesté   (exit 0)
```

## Bonus

**B1 - scan continu.** `trivy image --download-db-only` dans un volume `trivy-cache`, puis un conteneur
`trivy-server` (`trivy server --listen 0.0.0.0:4954 --token ...`) sur le réseau du registre. Les clients font
`trivy image --server http://trivy-server:4954 --token ...` : 0.5s, pas de base à télécharger sur chaque poste.
Sans token → erreur. La base n'est mise à jour qu'à un endroit.

**B2 - keyless.** Pas testé : il faut se connecter avec un navigateur (OIDC GitHub/Google) et ça ne marche pas avec
un registre local que Rekor ne connaît pas. Principe : `cosign sign registry/image@digest` sans `--key`, cosign récupère
un certificat de 10 minutes chez Fulcio lié à l'identité (mail ou workflow GitHub Actions) et la signature est
enregistrée dans le journal public Rekor. Vérification :
`cosign verify --certificate-identity=... --certificate-oidc-issuer=https://github.com/login/oauth image`.
- avantages : pas de clé privée à stocker ni à faire tourner, on sait QUI a signé (identité), tout est tracé dans Rekor
- inconvénients : dépend de services externes (Fulcio, Rekor), l'identité et le nom de l'image sont publics dans Rekor,
  il faut du réseau, et pour une entreprise il faut souvent héberger sa propre instance

**B3 - verified-run.sh.** `./verified-run.sh registry.local:5000/IMAGE:TAG [options docker run]` : récupère le digest,
`cosign verify` dessus, et lance `docker run` sur le digest (pas le tag, sinon le tag pourrait changer entre la
vérification et le run).
```
$ ./verified-run.sh registry.local:5000/shopapi:1.4.2 --rm --entrypoint id
signature OK : registry.local:5000/shopapi@sha256:0bb45158...
uid=1000(node) gid=1000(node) groups=1000(node),1000(node)
$ ./verified-run.sh registry.local:5000/demo:main-05 --rm
REFUSÉ : registry.local:5000/demo:main-05 (sha256:7fc4de81...) n'est pas signée par cosign.pub   (exit 1)
```

**B4 - trivy sbom.** `trivy sbom sbom.json` (SBOM de la première version de shopapi, sur base node) → 22 CVE trouvées sans
avoir besoin de l'image. Intérêt : si une CVE sort 6 mois après le build, on rescanne les SBOM gardés (ou attestés dans le
registre) de toutes les images en prod, c'est rapide et pas besoin de pull chaque image. Limite : on ne voit que ce qui
est dans le SBOM (ici les 4 CVE openssl d'alpine ne ressortent pas), et pas les secrets ni la config.
Remarque : en lançant trivy en local avec le même volume de cache que le serveur, erreur `database may be in use`,
le serveur garde le verrou.
