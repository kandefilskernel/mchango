# Base de données

| Fichier | Rôle |
|---------|------|
| `001_schema.sql` | Schéma PostgreSQL 16 (tables, journal chaîné, triggers) |
| `002_roles.sql` | Rôle applicatif `mchango_app` (pas de DELETE, journal en lecture/ajout) |
| `003_cash_witness.sql` | Cash : le receveur **et** un témoin désigné doivent confirmer |
| `004_auth.sql` | Verrouillage du PIN, un seul appareil actif par compte |
| `005_group_invitations.sql` | Codes d'invitation à partager (durée, nombre d'utilisations), taille maximale d'un groupe |
| `tests/001_checks.sql` | Double regard, anti-fraude, journal en ajout seul, détection de falsification |
| `tests/002_cash_witness.sql` | Règles du témoin (à lancer **après** `001_checks.sql`, sur la même base) |

Les choix sont expliqués dans [`docs/revue-schema.md`](../docs/revue-schema.md).

## Base de développement

`docker compose up -d` à la racine du dépôt démarre PostgreSQL et Redis, et applique les migrations au premier démarrage. Pour repartir de zéro :

```bash
docker compose down -v
```

## Lancer les tests de la base

Les tests insèrent des données : les lancer sur une base neuve, puis la remettre à zéro.

```bash
docker compose down -v && docker compose up -d --wait
```

```bash
docker compose exec -T postgres psql -U postgres -d mchango -q -f /db/tests/001_checks.sql
```

```bash
docker compose exec -T postgres psql -U postgres -d mchango -q -f /db/tests/002_cash_witness.sql
```

Chaque vérification affiche `OK` ; le script s'arrête au premier `ÉCHEC`.

> Sous Git Bash, préfixer les commandes `docker compose exec` par `MSYS_NO_PATHCONV=1` (sinon `/db/…` devient un chemin Windows).

## Règles pour l'API

- Se connecter avec un rôle membre de `mchango_app`, jamais avec le propriétaire des tables. En développement : `mchango_api` (créé par `infra/dev/init-db.sh`).
- Ouvrir chaque transaction d'écriture en déclarant l'auteur (fait par `Db.transaction()` dans l'API) :
  ```sql
  SELECT set_config('mchango.actor_type', 'user', true),
         set_config('mchango.actor_id', '<uuid>', true);
  ```
  Sans cela, toute écriture sur les tables métier est refusée.
- Ne jamais supprimer : changer le statut.
