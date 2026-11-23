# Base de données

| Fichier | Rôle |
|---------|------|
| `001_schema.sql` | Schéma PostgreSQL 16 (tables, journal chaîné, triggers) |
| `002_roles.sql` | Rôle applicatif `mchango_app` (pas de DELETE, journal en lecture/ajout) |
| `003_cash_witness.sql` | Cash : le receveur **et** un témoin désigné doivent confirmer |
| `004_auth.sql` | Verrouillage du PIN, un seul appareil actif par compte |
| `005_group_invitations.sql` | Codes d'invitation à partager (durée, nombre d'utilisations), taille maximale d'un groupe |
| `006_turns_cycles.sql` | Mode d'ordre et graine du tirage, ordre figé après démarrage, receveur = bénéficiaire du tour |
| `007_receipts.sql` | Numéro de reçu unique, attribué à la confirmation |
| `008_reminders.sql` | Clé d'unicité des notifications (un rappel par membre et par tour), erreur d'envoi |
| `009_pin_reset.sql` | Demandes « PIN oublié » (confirmation par un garant, expiration 48 h) |
| `010_backoffice.sql` | Back-office : motifs de blocage et de suspension, décisions de litige par l'équipe, droits sur `staff` |
| `011_support.sql` | Recours « PIN oublié » validé par l'équipe (`decided_by_staff`, `staff_note`) |
| `012_support_notes.sql` | Notes de suivi de l'équipe sur un membre (ajout seul), index de l'historique SMS |
| `013_language_en.sql` | Langue anglaise autorisée pour les comptes (`fr`, `sw`, `ln`, `en`) |
| `014_terms_signatures.sql` | Signature du règlement par chaque membre avant le démarrage (empreinte, ajout seul) |
| `015_feedback_ai.sql` | Avis des membres (`member_feedback`) et analyses de l'agent IA (`ai_reviews`), ajout seul |
| `016_contribution_risk.sql` | Score de risque de chaque déclaration (vert / orange / rouge), hors des chaînes de journal des groupes |
| `017_audit_chain_shards.sql` | Journal : la chaîne « global » est répartie par auteur (`user:<uuid>`, `staff`, `system`) pour ne plus être un goulot ; « global » est close |
| `018_group_category.sql` | Catégorie de tontine (`community`, `organization`, `workers`, `religion`), fixée à la création |
| `019_achats.sql` | Achats groupés : boutiques, zones, offres à paliers, commandes, paiements et retraits en boutique, partages ; chaîne de journal `offer:<uuid>` (voir `spec/achats.md`) |
| `020_turn_swaps.sql` | Échange de tour entre deux membres : demande, accord, bénéficiaires échangés ; unicité du bénéficiaire différée ; le bénéficiaire d'un tour ne change que par un échange accepté, avant tout paiement |
| `021_savings_goals.sql` | Objectifs d'épargne : un par adhésion, journalisés dans la chaîne du membre, partage facultatif |
| `022_attestations.sql` | Attestations de régularité : contenu figé et empreinte vérifiée par la base, code de vérification, retrait seul |
| `023_payday.sql` | Travailleurs : jour de paie et règle de report, jours fériés de la RDC (à valider), calcul des échéances |
| `024_private_slot_chains.sql` | Travailleurs : déclarations, confirmations et contestations dans une chaîne privée par payeur et par tour, au lieu de la chaîne du groupe |
| `025_president_fee.sql` | Part du président (0 à 10 % de la mise), figée au démarrage ; payée par le bénéficiaire du tour, confirmée par le président ; montant et parties vérifiés par la base |
| `tests/001_checks.sql` | Double regard, anti-fraude, journal en ajout seul, détection de falsification |
| `tests/002_cash_witness.sql` | Règles du témoin (à lancer **après** `001_checks.sql`, sur la même base) |
| `tests/003_turns_cycles.sql` | Ordre figé, bénéficiaire unique, receveur imposé (après `002`) |
| `tests/004_category.sql` | Catégorie par défaut, non modifiable, valeur inconnue refusée (après `003`) |
| `tests/005_achats.sql` | Achats : compteur calculé, jamais de double comptage, prix final fixé par la base, paiement et retrait confirmés par la seule boutique (après `004` ; attend quelques secondes la date de fin des offres) |

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

```bash
docker compose exec -T postgres psql -U postgres -d mchango -q -f /db/tests/003_turns_cycles.sql
```

```bash
docker compose exec -T postgres psql -U postgres -d mchango -q -f /db/tests/004_category.sql
```

```bash
docker compose exec -T postgres psql -U postgres -d mchango -q -f /db/tests/005_achats.sql
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
