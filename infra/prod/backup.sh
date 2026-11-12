#!/bin/sh
# Sauvegarde de la base : un fichier compressé par jour, les 14 derniers sont gardés.
# Copie hors du serveur si rclone est configuré avec une destination « sauvegarde: »
# (ex. Backblaze B2, 10 Go gratuits). À lancer chaque nuit (crontab, voir docs/mise-en-ligne.md).
set -eu
cd "$(dirname "$0")"
mkdir -p backups
file="backups/mchango-$(date -u +%Y%m%d-%H%M).sql.gz"

docker compose exec -T postgres pg_dump -U postgres --no-owner mchango | gzip > "$file"
# Une sauvegarde vide ne doit pas remplacer les bonnes
if [ "$(gzip -dc "$file" | head -c 100 | wc -c)" -lt 100 ]; then
    echo "sauvegarde vide : abandon" >&2
    rm -f "$file"
    exit 1
fi
ls -1t backups/mchango-*.sql.gz | tail -n +15 | xargs -r rm -f

if command -v rclone >/dev/null 2>&1 && rclone listremotes | grep -q '^sauvegarde:'; then
    rclone copy "$file" sauvegarde:mchango-backups/
fi
echo "sauvegarde : $file"
