docker network create reseau-api

docker run -d --name dogs-db --network reseau-api -p 3308:3306 -e MYSQL_ROOT_PASSWORD=root -e MYSQL_DATABASE=dogsdb -e MYSQL_USER=timeo -e MYSQL_PASSWORD=timeo mysql:8.0

cd dogapi
./mvnw spring-boot:run

docker build -t dogapi .
docker run -d --name dogapi --network reseau-api -p 8084:8084 -e SPRING_DATASOURCE_URL=jdbc:mysql://dogs-db:3306/dogsdb dogapi
docker logs dogapi

curl http://localhost:8084/api/v1/dogs
curl -X POST http://localhost:8084/api/v1/dogs -H "Content-Type: application/json" -d '{"name":"Rex","birthDate":"2018-05-10","breed":"Berger Allemand","sterilized":true}'
curl http://localhost:8084/api/v1/dogs/1
curl -X PUT http://localhost:8084/api/v1/dogs/1 -H "Content-Type: application/json" -d '{"name":"Rex","birthDate":"2018-05-10","breed":"Berger Allemand","sterilized":false}'
curl -X DELETE http://localhost:8084/api/v1/dogs/1
