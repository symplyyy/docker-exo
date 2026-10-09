docker build -t kennel-db .
docker images

docker run -d --name kennel -p 3307:3306 kennel-db
docker ps

docker exec -it kennel mysql -u root -proot
SHOW DATABASES;
USE kennelDB;
SHOW TABLES;
SELECT * FROM clients;
SELECT * FROM chiens;
SELECT * FROM chats;
exit
