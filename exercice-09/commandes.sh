docker network create reseau-exo9

docker run -d --name db-exo9 --network reseau-exo9 -p 3309:3306 -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=dogsdb -e MYSQL_USER=timeo -e MYSQL_PASSWORD=timeo mysql:8.0
docker run -d --name logs-db --network reseau-exo9 -p 3310:3306 -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=logsdb -e MYSQL_USER=timeo -e MYSQL_PASSWORD=timeo mysql:8.0

cd logapi
./mvnw spring-boot:run
cd ../crudapi
./mvnw spring-boot:run

cd ../logapi
docker build -t logapi .
cd ../crudapi
docker build -t crudapi .

docker run -d --name logapi --network reseau-exo9 -p 8085:8085 -e SPRING_DATASOURCE_URL=jdbc:mysql://logs-db:3306/logsdb logapi
docker run -d --name crudapi --network reseau-exo9 -p 8086:8086 -e SPRING_DATASOURCE_URL=jdbc:mysql://db-exo9:3306/dogsdb -e LOG_API_URL=http://logapi:8085/api/v1/logs crudapi
docker ps

curl http://localhost:8086/api/v1/dogs
curl -X POST http://localhost:8086/api/v1/dogs -H "Content-Type: application/json" -d '{"name":"Rex","birthDate":"2018-05-10","breed":"Berger Allemand","sterilized":true}'
curl http://localhost:8086/api/v1/dogs/1
curl http://localhost:8086/api/v1/dogs/99
curl -X POST http://localhost:8086/api/v1/dogs -H "Content-Type: application/json" -d '{"breed":"Chihuahua"}'
curl -X PUT http://localhost:8086/api/v1/dogs/1 -H "Content-Type: application/json" -d '{"name":"Rex","birthDate":"2018-05-10","breed":"Berger Allemand","sterilized":false}'
curl -X DELETE http://localhost:8086/api/v1/dogs/1

docker stop db-exo9
curl http://localhost:8086/api/v1/dogs
docker start db-exo9

curl http://localhost:8085/api/v1/logs
