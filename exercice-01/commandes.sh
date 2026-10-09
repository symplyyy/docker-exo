docker run -it --name mon-ubuntu ubuntu bash

apt update
apt install nginx -y
nginx -v
exit

docker commit mon-ubuntu ubuntu-nginx
docker images
