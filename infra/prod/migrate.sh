#!/bin/sh
# Applique les migrations de /db (001_…, 002_…) qui ne l'ont pas encore été, chacune dans une
# transaction, et les note dans schema_migrations. Sans risque à relancer.
# Crée aussi le rôle de connexion de l'API la première fois.
set -eu

psql -v ON_ERROR_STOP=1 -q -c "CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);"

for f in /db/0*.sql; do
    name=$(basename "$f")
    done_already=$(psql -tA -c "SELECT 1 FROM schema_migrations WHERE name = '$name'")
    if [ "$done_already" = "1" ]; then
        continue
    fi
    echo "migration : $name"
    # Une migration et son enregistrement réussissent ou échouent ensemble
    { cat "$f"; echo; echo "INSERT INTO schema_migrations (name) VALUES ('$name');"; } |
        psql -v ON_ERROR_STOP=1 -q --single-transaction
done

# Rôle de connexion de l'API (membre de mchango_app, défini dans 002_roles.sql)
psql -v ON_ERROR_STOP=1 -q -v pw="$MCHANGO_API_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE mchango_api LOGIN PASSWORD %L IN ROLE mchango_app', :'pw')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'mchango_api') \gexec
SELECT format('ALTER ROLE mchango_api PASSWORD %L', :'pw') \gexec
SQL

echo "base à jour"
