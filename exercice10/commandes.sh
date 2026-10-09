docker compose up -d --build
docker compose ps

curl http://localhost:8087/api/info/env
curl http://localhost:8087/api/info/app
curl http://localhost:8087/api/info/health

curl -X POST http://localhost:8087/api/notes -H "Content-Type: application/json" -d '{"title":"Test persistance","content":"cette note doit rester","category":"WORK","priority":"HIGH"}'
curl http://localhost:8087/api/notes

echo "fichier de test" > test.txt
curl -F "file=@test.txt" -F "noteId=4" http://localhost:8087/api/files/upload
curl http://localhost:8087/api/files

docker compose down
docker compose up -d
sleep 20
curl http://localhost:8087/api/notes
curl http://localhost:8087/api/files

docker compose down -v
docker compose up -d
sleep 20
curl http://localhost:8087/api/notes
curl http://localhost:8087/api/files

docker compose up -d --force-recreate app
sleep 15
curl http://localhost:8087/api/info/app
