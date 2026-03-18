up:
\tdocker compose -f infra/docker-compose.yml --env-file infra/.env up -d

down:
\tdocker compose -f infra/docker-compose.yml --env-file infra/.env down

migrate:
\tdocker exec -i $$(docker ps -qf name=mysql) \
\t  mysql -uroot -p$$(grep MYSQL_ROOT_PASSWORD infra/.env | cut -d= -f2) \
\t  < db/migrations/V1__init_schema.sql; \
\tdocker exec -i $$(docker ps -qf name=mysql) \
\t  mysql -uroot -p$$(grep MYSQL_ROOT_PASSWORD infra/.env | cut -d= -f2) \
\t  < db/migrations/V2__views.sql

seed:
\tdocker exec -i $$(docker ps -qf name=mysql) \
\t  mysql -uroot -p$$(grep MYSQL_ROOT_PASSWORD infra/.env | cut -d= -f2) \
\t  < db/seeds/seed_minimal.sql
