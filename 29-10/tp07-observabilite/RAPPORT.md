# TP07 - Rapport

Fichiers dans `solution/` : `compose.observability.yml`, `prometheus/prometheus.yml`, `prometheus/alerts.yml`,
`promtail/promtail.yml`, `loki/loki.yml`, `grafana/provisioning/...`, `grafana/dashboards/shop.json`, `load.sh`.
Captures dans `captures/`, sorties de commandes dans `evidence/`. La stack du TP04 tourne en mode prod (2 réplicas API).

```bash
cd ../tp04-compose-entreprise/solution && make prod-up
cd ../../tp07-observabilite/solution && docker compose -f compose.observability.yml up -d
./load.sh 1000
```
Prometheus : http://localhost:9090 · Grafana : http://localhost:3001 (admin/admin, dashboard « Shop SAS »)

## 1. Logs côté Docker

```
$ docker logs --since 5m shop-api-1 | jq
{"level":30,"time":1793282246119,"msg":"request completed","req":"/ready","status":200}
$ docker inspect shop-api-1 --format '{{.HostConfig.LogConfig}}'
{json-file map[max-file:3 max-size:10m]}
$ ls -la /var/lib/docker/containers/<id>/      (fait via un conteneur, sur Mac c'est dans la VM Docker Desktop)
-rw-r-----    1 root     root          1508 Oct 29 13:57 deaf50...-json.log
$ docker run --name nolog --log-driver none alpine echo "pas loggé" ; docker logs nolog
Error response from daemon: configured logging driver does not support reading
```

- **Sans `max-size`** : le fichier `-json.log` grossit sans limite. Au bout de 6 mois il peut faire des dizaines de Go
  et remplir le disque, et quand le disque est plein, Docker et les bases plantent.
- **stdout/stderr plutôt qu'un fichier** : c'est Docker qui récupère la sortie standard. Elle est donc visible avec
  `docker logs` et collectable par n'importe quel driver ou agent. Un fichier dans le conteneur est perdu avec la couche
  du conteneur, pas tourné, et invisible pour les outils.
- **Drivers** : `json-file` (défaut, fichier JSON lisible par `docker logs`), `local` (format interne compressé, plus
  compact, rotation par défaut), `journald` (envoie au journal systemd de l'hôte), `fluentd` / `awslogs` (envoient
  directement vers un collecteur ou CloudWatch, avec `docker logs` qui ne marche plus ou partiellement selon la version).
- **`mode: non-blocking` + `max-buffer-size`** : par défaut (blocking) si le driver est lent ou le collecteur en panne,
  l'écriture sur stdout bloque et l'application est ralentie. En non-blocking les logs passent par un buffer en
  mémoire, l'application n'est jamais bloquée, mais si le buffer est plein des lignes de logs sont perdues.

## 2. Métriques Docker et OOM

```
$ docker update --memory 64m --memory-swap 64m shop-api-1 ; ./load.sh 3000
shop-api-1    0.28%     30.95MiB / 64MiB      48.35%
OOMKilled=false RestartCount=0
```
Avec 64 Mo il ne se passe rien, l'API ne dépasse pas ~31 Mo. J'ai descendu à 28 Mo :
```
$ docker update --memory 28m --memory-swap 28m shop-api-1 ; ./load.sh 3000
$ docker events --filter type=container
oom shop-api-1
die shop-api-1 exitCode=137
start shop-api-1
$ docker inspect shop-api-1 --format '{{.State.OOMKilled}} {{.RestartCount}}'
OOMKilled=false RestartCount=1
```
Le noyau tue le processus (exit 137 = SIGKILL) et `restart: unless-stopped` le relance. `OOMKilled` est remis à false
au redémarrage, c'est `RestartCount` et `docker events` qui gardent la trace.

## 3. Stack d'observabilité

- **Prometheus** sur `default` + `shop_front` + `shop_back` (réseaux external). L'API est découverte par DNS
  (`dns_sd_configs` sur `api`) : les 2 réplicas apparaissent comme 2 cibles (`172.28.0.3:3000` et `172.28.0.4:3000`),
  pareil pour le worker sur 9100. Toutes les cibles sont `up` (`captures/prometheus-targets.png`).
- **Pourquoi pas `docker_sd_configs`** : `docker exec prometheus id` → `uid=65534(nobody)`, et la socket est
  `srw-rw---- root root`. Prometheus ne peut pas la lire sans le passer en root ou dans le groupe docker. Et donner la
  socket Docker à Prometheus revient à lui donner le contrôle total de la machine. Le DNS embarqué suffit.
- **cAdvisor** : la version de base (v0.49.1) ne donnait que des `id="/docker/<hash>"` sans nom de conteneur.
  Dans les logs : `Registration of the docker container factory failed`. Il a fallu passer en `ghcr.io/google/cadvisor:0.54.1`,
  monter directement `/var/run/docker.sock` (monter `/var/run` ne marche pas sur Docker Desktop) et
  `/run/containerd/containerd.sock` (Docker 29 utilise le store containerd).
- **Loki + Promtail** : Promtail lit tous les conteneurs via la socket (`docker_sd_configs`), labels `container`,
  `service` et `project` depuis les labels compose, et extrait `level` du JSON. Les erreurs `400 Bad Request` au
  démarrage de promtail viennent des vieux logs d'autres conteneurs de ma machine, rejetés par Loki parce que trop anciens.
- **Grafana** : datasources et dashboard provisionnés par fichiers, rien n'est fait à la main. Accès anonyme en lecture
  activé pour pouvoir faire les captures en headless.
- **Alertes** (`prometheus/alerts.yml`) : `ApiDown`, `Api5xx` (> 5 %), `ApiLatencyP95` (> 500 ms),
  `ContainerRestarting`, `ContainerMemoryHigh` (> 90 % de la limite).

Pour `ContainerRestarting` j'avais d'abord mis `changes(container_start_time_seconds[10m])` (cAdvisor), mais cette
valeur ne change pas sur un `docker restart`. J'utilise `changes(process_start_time_seconds{job=~"api|worker"}[10m])`
que l'API (prom-client) et le worker (prometheus_client) exposent.

Alertes passées en `firing` (pannes provoquées : base arrêtée, worker redémarré, API arrêtée, mémoire réduite) :
```
firing  Api5xx
firing  ApiDown
firing  ContainerRestarting  172.28.0.3:3000
firing  ContainerRestarting  172.28.0.4:3000
firing  ContainerRestarting  172.29.0.5:9100
```
`ContainerMemoryHigh` n'a pas réussi à passer en firing : l'API utilise ~18 Mo au repos, à 20 Mo elle est tuée en
boucle par l'OOM avant de rester 1 minute au-dessus de 90 %, et à 23-34 Mo elle reste sous les 90 %.

Requêtes :
```
{service="api"} | json | level="50"
{"level":50,...,"req":{"method":"GET","url":"/products",...}   (base arrêtée)
{service="worker"} |= "rejected"
{"level":"INFO","msg":"commande 1793283319010 -> rejected"}
sum(rate(http_request_duration_seconds_count[1m])) by (status)
   200  0.40
```

Captures : `captures/dashboard-sous-charge.png` (pendant `load.sh`, ~420 req/s), `captures/prometheus-alertes.png`,
`captures/prometheus-targets.png`.

## 4. Corrélation

Sans formateur, j'ai injecté la panne moi-même : base de données arrêtée. Dans Grafana :
1. le panneau « Requêtes/s par status » montre des 503 et 500 qui apparaissent, et l'alerte `Api5xx` passe en firing
2. dans les logs (`{service="api"} | json | level="50"`) : erreurs sur `/products` au moment où la base ne répond plus
3. vérification avec docker : `docker compose ps` → `shop-db-1` arrêté, `docker events` → `die shop-db-1`

Bonus non faits.
