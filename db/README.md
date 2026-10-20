# Base de données

| Fichier | Rôle |
|---------|------|
| `001_schema.sql` | Schéma PostgreSQL 16 (tables, journal chaîné, triggers) |
| `002_roles.sql` | Rôle applicatif `mchango_app` (pas de DELETE, journal en lecture/ajout) |
| `tests/001_checks.sql` | Vérifications : double regard, anti-fraude, journal en ajout seul, détection de falsification |

Les choix sont expliqués dans [`docs/revue-schema.md`](../docs/revue-schema.md).

## Lancer les tests (Docker Desktop, PowerShell, depuis la racine du dépôt)

```powershell
docker run -d --name mchango-pg -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=mchango -v "${PWD}/db:/db:ro" postgres:16
```

```powershell
docker exec mchango-pg psql -U postgres -d mchango -v ON_ERROR_STOP=1 -q -f /db/001_schema.sql -f /db/002_roles.sql
```

```powershell
docker exec mchango-pg psql -U postgres -d mchango -q -f /db/tests/001_checks.sql
```

Chaque vérification affiche `OK` ; le script s'arrête au premier `ÉCHEC`. Les tests insèrent des données : recréer le conteneur pour les relancer.

```powershell
docker rm -f mchango-pg
```

## Règles pour l'API

- Se connecter avec un rôle membre de `mchango_app`, jamais avec le propriétaire des tables.
- Ouvrir chaque transaction d'écriture par :
  ```sql
  SET LOCAL mchango.actor_type = 'user';      -- 'user' | 'staff' | 'system'
  SET LOCAL mchango.actor_id   = '<uuid>';
  SET LOCAL mchango.device_id  = '<uuid>';    -- facultatif
  ```
  Sans cela, toute écriture sur les tables métier est refusée.
- Ne jamais supprimer : changer le statut.
