#!/bin/sh
# Crée infra/prod/.env avec des secrets neufs et des adresses gratuites en sslip.io
# (api.<ip>.sslip.io et admin.<ip>.sslip.io pointent vers l'IP du serveur, HTTPS compris).
# Ne remplace jamais un .env existant : les secrets perdus rendraient la base illisible.
#   ./gen-secrets.sh            (détecte l'IP publique)
#   ./gen-secrets.sh 1.2.3.4    (IP donnée)
set -eu
cd "$(dirname "$0")"

if [ -f .env ]; then
    echo ".env existe déjà : rien n'est changé." >&2
    exit 1
fi

ip=${1:-$(curl -fsS https://api.ipify.org)}
dashed=$(echo "$ip" | tr . -)
rand() { openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48; }

umask 077
cat > .env <<EOF
# Généré le $(date -u +%Y-%m-%d) par gen-secrets.sh. À SAUVEGARDER hors du serveur (gestionnaire de mots de passe).
API_DOMAIN=api.$dashed.sslip.io
ADMIN_DOMAIN=admin.$dashed.sslip.io

POSTGRES_PASSWORD=$(rand)
MCHANGO_API_DB_PASSWORD=$(rand)
JWT_SECRET=$(rand)
OTP_PEPPER=$(rand)
STAFF_JWT_SECRET=$(rand)
STAFF_SECRET_KEY=$(openssl rand -base64 32)

STAFF_SESSION_HOURS=8
REMINDERS_ENABLED=1
# PILOTE FERMÉ : pas de fournisseur SMS, les codes sont dans « docker compose logs api ».
# Remettre à 0 dès qu'un fournisseur SMS est branché.
SMS_CONSOLE_PILOT=1
EOF

echo "Fichier .env créé (droits 600)."
echo "  API         : https://api.$dashed.sslip.io"
echo "  Back-office : https://admin.$dashed.sslip.io"
echo "Copiez .env dans votre gestionnaire de mots de passe : sans lui, impossible de relire la base."
