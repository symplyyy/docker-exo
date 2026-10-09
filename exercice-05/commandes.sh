docker network create reseau-bdd
docker volume create mysql-data

docker run -d --name mysql --network reseau-bdd --restart always -v mysql-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=ecole -e MYSQL_USER=timeo -e MYSQL_PASSWORD=timeo mysql:8.0
docker run -d --name adminer --network reseau-bdd --restart always -p 8082:8080 adminer
docker ps

docker rm -f mysql
docker run -d --name mysql --network reseau-bdd --restart always -v mysql-data:/var/lib/mysql -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=ecole -e MYSQL_USER=timeo -e MYSQL_PASSWORD=timeo mysql:8.0

docker exec -it mysql bash
kill 1
docker ps

docker compose up -d
