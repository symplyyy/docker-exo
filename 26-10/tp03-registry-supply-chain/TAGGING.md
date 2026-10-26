# Politique de tags

| Tag | Exemple | Immuable | Usage |
|---|---|---|---|
| version semver | `1.4.2` | oui | release, déployé en prod |
| commit | `77bed97` | oui | traçabilité, déploiements de test |
| version mineure | `1.4` | non, suit le dernier patch | dev / tests |
| branche | `main-77bed97`, `pr-12` | oui, nettoyé par `retention.sh` | CI |
| `latest` | | | interdit |

- un tag semver ou commit n'est jamais re-poussé avec un autre contenu
- `latest` est interdit en prod : il change sans prévenir, on ne sait pas ce qui tourne, et deux nœuds peuvent
  avoir deux versions différentes (c'est ce qui a cassé la prod le vendredi soir)
- en prod on référence l'image par digest, le tag est juste là pour la lisibilité :

```yaml
services:
  api:
    image: registry.local:5000/shopapi:1.4.2@sha256:0bb45158299bb0776abe24c0cf8408281a9fee937f5e4d0b8458aac4cfe3e54f
```

- retag sans pull :

```bash
./tools.sh crane tag registry.local:5000/shopapi:1.4.2 1.4
./tools.sh crane copy registry.local:5000/shopapi:1.4.2 registry.local:5000/shopapi-prod:1.4.2
```
