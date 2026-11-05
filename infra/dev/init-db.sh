#!/bin/sh
# Initialisation de la base de DÉVELOPPEMENT (exécuté une seule fois par l'image postgres).
# Applique les migrations dans l'ordre, puis crée le rôle de connexion de l'API.
set -eu

for f in /db/0*.sql; do
    echo "migration : $f"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -f "$f"
done

# Mot de passe de développement uniquement : en production, il vient d'un gestionnaire de secrets.
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q \
    -c "CREATE ROLE mchango_api LOGIN PASSWORD '${MCHANGO_API_DB_PASSWORD}' IN ROLE mchango_app;"
