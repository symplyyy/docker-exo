docker network create mon-reseau
docker network ls

docker run -it --name c1 --network mon-reseau ubuntu bash
apt update
apt install iputils-ping -y
exit

docker commit c1 ubuntu-ping

docker start c1
docker run -dit --name c2 ubuntu-ping
docker network connect mon-reseau c2
docker network inspect mon-reseau

docker exec -it c1 ping c2
docker exec -it c2 ping c1
