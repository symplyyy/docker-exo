docker build -t mon-site .
docker run -d -p 8081:80 --name mon-site mon-site
docker ps
