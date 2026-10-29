# TP05 - Rapport

Scripts dans `solution/` : `backup.sh`, `restore.sh`, `upgrade-pg.sh`, `checksum.sh`, `compose.backup.yml`, `compose.pg16.yml`.
J'ai mis le port du starter en 5435 car 5433 est déjà pris sur ma machine. Sorties complètes dans `evidence/`.

## 1. Anatomie du stockage

Montages de la base du TP04 :
```
{"Type":"volume","Name":"shop_pgdata","Source":"/var/lib/docker/volumes/shop_pgdata/_data","Destination":"/var/lib/postgresql/data","RW":true}
{"Type":"bind","Source":".../db/init.sql","Destination":"/docker-entrypoint-initdb.d/init.sql","RW":false}
{"Type":"bind","Source":".../secrets/db_password.txt","Destination":"/run/secrets/db_password","RW":false}
```
`shop_pgdata` fait 48MB (`docker system df -v`). Sur Docker Desktop le chemin `/var/lib/docker/volumes/...` est dans la VM Linux, pas sur le Mac.

**Couche du conteneur vs volume** : `docker exec db touch /tmp/x` puis `docker diff` → `A /tmp/x` apparaît.
Un fichier créé dans `/var/lib/postgresql/data` n'apparaît pas dans `docker diff` : il est dans le volume, pas dans la
couche du conteneur (qui disparaît avec le conteneur).

**Cycle de vie** (testé sur une copie `voltest`) :

| commande | volume pgdata |
|---|---|
| `docker compose down` | gardé |
| `docker compose rm` | gardé |
| `docker volume prune` | gardé (depuis Docker 23 ne supprime que les volumes anonymes) |
| `docker volume prune -a` | **supprimé** (volume plus utilisé par aucun conteneur) |
| `docker compose down -v` | **supprimé** |

**Volume anonyme** : `docker run -d postgres:16-alpine` crée un volume au nom aléatoire (`45d86007f7e6...`) car l'image
déclare `VOLUME /var/lib/postgresql/data`. Au `docker rm` il reste là, orphelin. Avec `docker rm -v` il est supprimé.
C'est un piège : soit on accumule des volumes qu'on ne sait plus à quoi ils servent, soit on croit avoir des données
alors qu'au prochain `docker run` un nouveau volume vide est créé.

**Bind mount / volume / tmpfs** :
- bind mount : fichiers de l'hôte (code en dev, configs). Sur Docker Desktop Mac/Windows c'est lent car les fichiers
  passent par le partage de fichiers entre le Mac et la VM
- volume nommé : données des bases, géré par Docker, rapide car directement dans la VM
- tmpfs : en RAM, pour des fichiers temporaires ou sensibles qui ne doivent pas être écrits sur disque

**init.sql pas rejoué** : l'entrypoint postgres ne lance `/docker-entrypoint-initdb.d` que si le répertoire de données
est vide. Au redémarrage le volume contient déjà la base donc rien n'est rejoué. Pour forcer : supprimer le volume
(`docker compose down -v`), ou lancer le script à la main avec `psql`.

## 2. Sauvegarde / restauration

`backup.sh` : `pg_dump -Fc` horodaté dans `backups/`, avec `RAW=1` en plus une sauvegarde brute du volume
(`docker run --rm -v vol:/data:ro alpine tar czf ...`), rétention des 7 derniers. Tout passe par des conteneurs.

La sauvegarde brute est incohérente si postgres tourne pendant le `tar` : les fichiers sont copiés à des moments
différents pendant que la base écrit. Pour qu'elle soit cohérente : arrêter la base avant (c'est ce que fait mon script),
ou `pg_backup_start()` / `pg_backup_stop()` + garder les WAL, ou faire un snapshot du disque.

Preuve :
```
$ ./seed.sh
 100000 | e1bd868f1ce4ab49e8314e139b5d6a0c
$ RAW=1 ./backup.sh
dump logique : backups/shop-20261029-144513.dump (1.5M)
sauvegarde brute : backups/shopdata_pgdata-20261029-144513.tar.gz ( 13M)
$ docker compose down -v
 Volume shopdata_pgdata  Removed
$ docker compose up -d --wait
   tables orders : 0
$ ./restore.sh backups/shop-20261029-144513.dump
restauré : backups/shop-20261029-144513.dump
$ ./checksum.sh
100000 e1bd868f1ce4ab49e8314e139b5d6a0c
=> checksums identiques
```

Sidecar `compose.backup.yml` (projet séparé qui rejoint `shop_back` du TP04, `SCHEDULE: "@every 1m"`) :
```
backup-1  | Creating dump of shop database from db...
backup-1  | SQL backup created successfully
backups-tp04/last:
   shop-20261029-134644.sql.gz
   shop-20261029-134744.sql.gz
   shop-20261029-134844.sql.gz
   ...
```
Le healthcheck de l'image restait en `starting`, donc je ne lance pas ce fichier avec `--wait`.

## 3. PostgreSQL 14 → 16

Juste changer le tag :
```
FATAL:  database files are incompatible with server
DETAIL:  The data directory was initialized by PostgreSQL version 14, which is not compatible with this version 16.4.
```
Le format des fichiers de données change entre versions majeures. PG16 ne sait pas lire un répertoire PG14, il faut
soit un dump/restore, soit `pg_upgrade`.

`upgrade-pg.sh` :
```
== 1. checksum PG14
14.13
100000 e1bd868f1ce4ab49e8314e139b5d6a0c
== 2. dumps
4.9M backups/all-20261029-145241.sql
1.5M backups/shop-20261029-145241.dump
== 3. arrêt PG14 (volume pgdata conservé)
== 4. PG16 sur le volume pgdata16
16.4
== 5. restauration
indisponibilité : 7s
== 6. checksum PG16
100000 e1bd868f1ce4ab49e8314e139b5d6a0c
VERDICT : OK, migration sans perte
```

**Retour arrière** : l'ancien volume `shopdata_pgdata` n'est pas touché. Il suffit de relancer sans `compose.pg16.yml` :
`docker compose -f compose.yml up -d --force-recreate db` → `14.13`, même checksum (testé). Attention, les écritures
faites sur PG16 entre-temps seraient perdues.

**pg_dumpall vs pg_dump** : `pg_dump` sauvegarde une seule base (format custom `-Fc` possible, restauration sélective
avec `pg_restore`). `pg_dumpall` sauvegarde tout le cluster en SQL texte, y compris les rôles, mots de passe et
tablespaces (les « globals »), que `pg_dump` ne contient pas.

**Pourquoi un nouveau volume** : si la restauration rate, l'ancienne base est intacte et le retour arrière prend
quelques secondes. En écrasant, la seule copie qui reste est le dump.

**Réduire l'indisponibilité** : `pg_upgrade --link` (image `tianon/postgres-upgrade:14-to-16` qui a les deux versions)
crée des liens vers les fichiers au lieu de tout recopier, quelques secondes même sur une grosse base. Ou réplication
logique : PG16 se synchronise avec PG14 pendant que PG14 tourne encore, puis on bascule l'application, l'arrêt ne dure
que le temps de la bascule.

## 4. Redis

- `--save 60 1` (snapshot RDB) : snapshot toutes les 60s s'il y a eu au moins 1 écriture → on peut perdre jusqu'à
  ~60s de données (plus si le snapshot échoue)
- `--appendonly yes` (AOF, `appendfsync everysec` par défaut) : chaque écriture est ajoutée au fichier → on perd au
  maximum ~1s

Dans notre stack Redis contient le cache des produits (perdable, il se reconstruit depuis postgres) et la file
`orders:queue`. Les commandes sont aussi en base (status `pending`) mais une commande perdue dans la file ne serait jamais
traitée par le worker. Donc AOF est justifié (c'est ce que j'ai mis dans le TP04 : `--appendonly yes` + volume `redisdata`).

Bonus non faits.
