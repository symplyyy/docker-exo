# TP08 - Livrables

Lancement (depuis le dossier du TP04) :

```bash
docker compose -f compose.yml -f compose.prod.yml -f ../../../30-10/tp08-hardening/solution/compose.hardened.yml up -d --wait
../../../30-10/tp08-hardening/solution/audit.sh shop
```

## 1. Mesure

`audit.sh [projet]` : utilisateur, privileged, capabilities, rootfs, mémoire, PIDs, no-new-privileges, socket Docker.
Code retour 1 s'il y a un écart.

| | écarts | détail |
|---|---|---|
| avant (TP04 prod) | 16 | db, redis et traefik en root, rootfs en écriture, pas de `cap_drop`, aucune limite de PIDs, socket dans traefik |
| après (`compose.hardened.yml`) | 1 | `docker_sock` sur `socket-proxy`, c'est son rôle. 0 écart sur les services applicatifs |

Sorties : `evidence/audit-avant.txt`, `evidence/audit-apres.txt`.

docker-bench-security : **105 checks, score 0, 28 WARN** (`evidence/docker-bench.txt`). Sous Docker Desktop il a fallu
retirer les montages `/etc` et `/var/lib` (erreur de montage dans la VM) et forcer `DOCKER_API_VERSION=1.44`
(le client de l'image est trop vieux pour Docker 29). Le bench audite tous les conteneurs de ma machine, pas seulement la stack.
5 WARN prioritaires :

1. **5.31** socket Docker montée dans un conteneur (traefik) → accès root à l'hôte
2. **4.1 / 5.25** conteneurs en root et sans `no-new-privileges`
3. **5.10 / 5.28** pas de limite mémoire / PIDs → un conteneur peut faire tomber l'hôte (fork bomb, fuite mémoire)
4. **5.12** rootfs en écriture → un attaquant peut modifier les binaires ou poser des fichiers
5. **2.8** pas de user namespaces → root dans le conteneur = root sur l'hôte en cas d'évasion

## 2. Expériences

Sorties : `evidence/experiences-1.txt`, `evidence/experiences-2.txt`, `evidence/caps-postgres.txt`.

| Mesure | Expérience | Résultat |
|---|---|---|
| `--read-only` | `touch /x` | `Read-only file system` ; avec `--tmpfs /tmp`, `touch /tmp/x` OK |
| `--cap-drop ALL` | `chown nobody /etc/motd` | `Operation not permitted` → il faut `CHOWN` |
| | `ping 1.1.1.1` | marche quand même : Docker met `net.ipv4.ping_group_range=0 2147483647`, ping utilise un socket ICMP non privilégié. Avec `ping_group_range="1 0"` → `permission denied`, il faut alors `NET_RAW` |
| | `apk add curl` | marche (exit 0) car tous les fichiers installés appartiennent à root. Un paquet qui fait des `chown` vers un autre utilisateur aurait besoin de `CHOWN`, `FOWNER`, `DAC_OVERRIDE` |
| `no-new-privileges` | `sudo id` (binaire setuid) en utilisateur 1000 | sans : `uid=0(root)` ; avec : `The "no new privileges" flag is set, which prevents sudo from running as root` |
| `--pids-limit 50` | 100 `sleep 60 &` | sans : 105 processus ; avec : `sh: can't fork: Resource temporarily unavailable` |
| `--memory 32m` | `python -c "x='a'*100_000_000"` | `ExitCode=137 OOMKilled=true` |
| `--user 1000` | `id` puis écrire dans un volume créé par root | `uid=1000 gid=0` ; `touch /data/g: Permission denied` : le volume appartient à root, il faut le préparer (`chown`) ou utiliser le même uid partout |
| seccomp | `unshare --user id` | défaut : `Operation not permitted` ; `seccomp=unconfined` : OK. Le profil par défaut est en liste blanche (`defaultAction: SCMP_ACT_ERRNO`, 426 noms de syscalls autorisés toutes archis), il bloque une quarantaine de syscalls dangereux (`mount`, `unshare`, `keyctl`, `kexec_load`, `reboot`, `init_module`, `bpf`...) |

**Capabilities de PostgreSQL (essai/erreur)** avec l'image en root :

| cap_add | résultat |
|---|---|
| aucune | `chmod: Operation not permitted`, `failed switching to "postgres"` → crash |
| CHOWN | idem |
| CHOWN SETUID SETGID | démarre (les `chmod` échouent mais ne sont pas bloquants) |
| CHOWN SETUID SETGID FOWNER DAC_OVERRIDE | démarre sans erreur |

SETUID/SETGID servent au `su-exec postgres` de l'entrypoint, CHOWN/FOWNER/DAC_OVERRIDE au `chown`/`chmod` du dossier de données.
J'ai finalement lancé postgres directement en `user: "70:70"` : l'entrypoint saute la partie root, il ne faut **aucune**
capability (le volume appartient déjà à 70).

Traefik : en root sur le port 80 il faut `NET_BIND_SERVICE` (port < 1024). Je le fais écouter sur 8000 en `65534`
(publié en `80:8000`) → aucune capability.

## 3. compose.hardened.yml : menace réduite par directive

| Directive | Services | Menace réduite |
|---|---|---|
| `read_only: true` + `tmpfs` ciblés | tous | modification des binaires/config, dépôt d'un webshell ou d'un outil après une faille |
| `cap_drop: [ALL]` sans `cap_add` | tous | utilisation des capabilities root restantes (chown, kill d'autres processus, raw sockets, bind de ports privilégiés...) |
| `no-new-privileges` | tous (prod + proxy) | élévation via un binaire setuid (`sudo`, `su`, `passwd`) |
| `deploy.resources.limits.pids` | tous | fork bomb qui épuise les PIDs de l'hôte |
| limites CPU/mémoire (prod) | tous | un conteneur qui consomme toute la machine (DoS, fuite mémoire) |
| `user: "70:70"` (db), `"999:1000"` (redis), `"65534:65534"` (traefik) | db, redis, traefik | root dans le conteneur, plus d'impact en cas d'évasion |
| socket retirée de traefik (`volumes: !reset []`) + `socket-proxy` | traefik | une faille dans traefik donnait le contrôle total de Docker (= root sur l'hôte) |
| `socket-proxy` : `POST: 0`, seulement `CONTAINERS`/`NETWORKS`, réseau `socket` en `internal` | proxy | même avec le proxy compromis : lecture seule, pas de création de conteneur ; seul traefik peut le joindre |
| `user: "65534:0"` sur le proxy | proxy | le proxy n'est pas root, il a juste le groupe 0 pour lire la socket (`root:root 660`) |

Validation : `docker compose ... up -d --wait` tout healthy, smoke test du TP04 vert, proxy : `GET /containers/json` 200,
`POST /containers/create` 403, `GET /images/json` 403 (`evidence/validation.txt`).

## 4. daemon.json

| Option | Pourquoi |
|---|---|
| `no-new-privileges: true` | appliqué par défaut à tous les conteneurs, même si on oublie dans le compose |
| `icc: false` | les conteneurs du bridge par défaut ne peuvent plus se parler |
| `live-restore: true` | les conteneurs continuent de tourner pendant un redémarrage/mise à jour du daemon |
| `userland-proxy: false` | publication de ports par iptables seulement, pas de processus `docker-proxy` par port |
| `userns-remap: default` | root du conteneur = uid 100000+ sur l'hôte, une évasion ne donne pas root |
| `log-opts` rotation | les logs ne remplissent plus le disque, même pour les conteneurs lancés sans `logging:` |
| `default-ulimits` | limite le nombre de fichiers ouverts par conteneur |

Effets de bord :
- `icc: false` ne concerne que le **bridge par défaut** (`docker0`). Notre stack compose utilise ses propres réseaux
  (`shop_front`, `shop_back`), donc elle n'est pas touchée. Ce qui casse : les conteneurs lancés avec `docker run` sans
  `--network` qui se parlent entre eux (il faudrait des `--link`, obsolètes, ou un réseau utilisateur).
- `userns-remap` : les fichiers des volumes existants appartiennent à de vrais uid (0, 70, 999...). Après activation,
  Docker utilise un autre dossier (`/var/lib/docker/100000.100000/`), les anciens volumes ne sont plus visibles, et si on
  les recopie ils apparaissent comme `nobody` dans le conteneur → postgres ne peut plus lire `pgdata`. Il faut faire un
  `chown` vers la plage remappée (ex. 70 → 100070). Incompatible aussi avec `--privileged`, `--pid=host`, `--net=host`
  sans `--userns=host`.
- Alternative : Docker **rootless** (le daemon lui-même tourne sans root), mais pas de ports < 1024 sans configuration,
  réseau plus lent (slirp4netns / pasta).

Non testé sur ma machine : le `daemon.json` de Docker Desktop se modifie dans les réglages de l'application et redémarre
la VM, je ne l'ai pas appliqué.

Bonus non faits.
