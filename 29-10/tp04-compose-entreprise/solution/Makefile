PROD = docker compose -f compose.yml -f compose.prod.yml

.PHONY: up down ps logs tools prod-up prod-down prod-ps migrate test

up:
	docker compose up -d --build --wait

down:
	docker compose down

ps:
	docker compose ps

logs:
	docker compose logs -f --tail 50

tools:
	docker compose --profile tools up -d --wait

prod-up:
	$(PROD) up -d --wait --remove-orphans

prod-down:
	$(PROD) down

prod-ps:
	$(PROD) ps

migrate:
	@test -n "$(M)" || (echo "usage: make migrate M=002-add-sku.sql" && exit 1)
	MIGRATION=$(M) docker compose run --rm migrate

test:
	./smoke-test.sh
