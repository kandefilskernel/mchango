# Revue du schéma `tontine_schema.sql`

> 20 octobre 2026 — version corrigée : [`db/001_schema.sql`](../db/001_schema.sql), tests : [`db/tests/001_checks.sql`](../db/tests/001_checks.sql)

La base est saine : pas de table de solde, statuts explicites, unicité de l'ID de transaction, idempotence hors ligne (`offline_id`), journal en ajout seul. Les corrections ci-dessous sont classées par gravité.

## Critique — le journal d'audit ne tenait pas sa promesse

### 1. La chaîne de hash « fourche » dès qu'il y a de la concurrence

Le trigger lit le dernier hash (`ORDER BY id DESC LIMIT 1`) **sans verrou**. Deux insertions simultanées lisent le même `prev_hash` et créent deux branches.

**Mesuré** (PostgreSQL 16, 8 clients × 100 insertions en parallèle) :

| Schéma | Lignes | `prev_hash` en double (fourches) |
|--------|--------|----------------------------------|
| Original | 800 | **590** |
| Corrigé | 801 | **0**, chaîne vérifiée intacte |

Correction : table `audit_chain_heads` verrouillée `FOR UPDATE` dans le trigger, et `seq` continu par chaîne avec `UNIQUE (chain_id, seq)`.

### 2. Le hash n'est pas vérifiable de façon fiable

- `created_at::text` dépend des paramètres de session (`TimeZone`, `DateStyle`) : le même événement donne un hash différent selon la connexion qui vérifie.
- Les champs sont concaténés sans séparateur : `actor_type || actor_id || action…` est ambigu.
- `payload::text` (JSONB) est une sérialisation propre à PostgreSQL, pénible à reproduire en Dart.

Correction : fonction `audit_hash()` avec un format fixe (date UTC au format ISO à la milliseconde, champs séparés par `\n`, préfixe de version `mchango-v1`), et un payload stocké en `TEXT` haché **tel quel** : l'app Flutter vérifie en hachant les octets reçus, sans reproduire aucune sérialisation.

### 3. Une seule chaîne pour toute la plateforme

Un membre ne peut pas vérifier l'historique de son groupe sans recevoir les événements de **tous** les autres groupes (fuite de données), et toutes les écritures se bloquent mutuellement.

Correction : une chaîne par groupe (`chain_id = 'group:<uuid>'`) et une chaîne `global` pour le reste.

### 4. Le journal pouvait être vidé

Les triggers `FOR EACH ROW` ne se déclenchent pas sur `TRUNCATE`. Et si l'API se connecte avec le propriétaire des tables, elle peut désactiver les triggers.

Correction : trigger `BEFORE TRUNCATE`, rôle applicatif `mchango_app` sans droit `UPDATE`/`DELETE`/`TRUNCATE` sur le journal ni accès aux têtes de chaîne ([`db/002_roles.sql`](../db/002_roles.sql)).

### 5. Rien ne garantissait que chaque changement soit journalisé

Le journal dépendait de la discipline du code de l'API : un oubli, et une confirmation existe sans trace.

Correction : triggers `AFTER INSERT OR UPDATE` sur les tables métier, qui écrivent dans le journal **dans la même transaction**. L'API déclare l'auteur via `SET LOCAL mchango.actor_type / actor_id` ; sans auteur, l'écriture est refusée.

## Important — intégrité métier

| # | Problème | Correction |
|---|----------|------------|
| 6 | `ON DELETE CASCADE` : supprimer un groupe effaçait tours, cotisations et confirmations. | Plus de cascade ; suppression physique interdite par trigger sur les tables métier (on clôture, on ne supprime pas). |
| 7 | Rien n'empêchait un bénéficiaire, payeur ou cycle d'appartenir à un **autre groupe**. | Clés étrangères composites `(id, group_id)`. |
| 8 | Pas de receveur sur la cotisation : en mode trésorier, impossible de savoir qui doit confirmer. N'importe quel membre pouvait confirmer. | `receiver_membership_id` + trigger : seul le receveur peut `confirm`. Payeur ≠ receveur. |
| 9 | ID de transaction unique **par groupe** : le même reçu M-Pesa pouvait servir dans deux groupes. | Unicité `(method, tx_reference)` sur toute la plateforme, référence normalisée (majuscules, sans espaces). |
| 10 | `UNIQUE (cycle_id, payer)` bloquait toute re-déclaration après un rejet. Pas d'état « rejetée ». | Statut `rejected` ; unicité partielle `WHERE status <> 'rejected'`. |
| 11 | `late` était un statut exclusif : une cotisation en retard ne pouvait pas être « déclarée » puis « confirmée ». | Booléen `is_late`, indépendant du statut. |
| 12 | Mobile Money sans ID de transaction accepté. | `CHECK (method = 'cash' OR tx_reference IS NOT NULL)`. |
| 13 | `NUMERIC(14,2)` : exact en base, mais Dart n'a pas de décimal natif ; le risque est de passer par des `double` côté mobile. | `BIGINT` en unités mineures (`amount_minor` : francs pour CDF, cents pour USD). |

## À compléter

| # | Manque | Ajout |
|---|--------|-------|
| 14 | Pas de table d'appareils : impossible de lier un compte à un téléphone, de révoquer un appareil volé, de stocker le jeton push ou la clé de signature. | Table `devices`. |
| 15 | `pin_hash NOT NULL` + `memberships.user_id` obligatoire : impossible d'inviter quelqu'un qui n'a pas encore de compte. | Table `invitations` (par numéro, jeton haché, expiration). |
| 16 | Statuts en `VARCHAR` libre (`disputes`, `notifications`). | Types énumérés. |
| 17 | Téléphone et langue sans contrôle. | `CHECK` format E.164 et langue `fr/sw/ln`. |
| 18 | `totp_secret` en clair et facultatif alors que la 2FA est « obligatoire ». | `totp_secret_enc` (chiffré par l'application) + `totp_enabled_at` ; l'API refuse toute action tant qu'il est NULL. |
| 19 | Rôle de membre `admin` ambigu avec `president` et avec le back-office. | Retiré des rôles de membre. |

## Ce qui n'est pas réglé par le SQL (à garder en tête)

- **Un superutilisateur PostgreSQL peut toujours tout réécrire**, y compris recalculer une chaîne entière cohérente. Le journal protège contre les erreurs et les accès applicatifs, pas contre l'hébergeur ou un admin base de données malveillant. Les vraies protections contre ce cas : les clients qui mémorisent le dernier hash de leur groupe, les signatures des appareils (colonne `signature`, prévue mais pas encore vérifiée par la base) et, en V2, un ancrage public périodique.
- **Le PIN** : 4 à 6 chiffres = au plus un million de combinaisons. Même haché en argon2id, il se casse hors ligne si la base fuit. Le PIN doit servir à déverrouiller l'appareil ; l'authentification serveur doit reposer sur la clé de l'appareil + OTP, avec limitation stricte des essais.
- **Les OTP** n'ont pas de table : à mettre dans Redis avec expiration (5 min) et compteur d'essais.
- **`trust_scores`** : ne pas le calculer au MVP. Un score de confiance sur des personnes ressemble à du scoring de crédit : vérifiez avec un juriste les règles applicables (protection des données, BCC) avant de l'afficher ou de le partager avec des partenaires.
- **`late_penalty_rule`** : les pénalités restent payées de membre à membre. Si Mchango les encaissait, on retomberait dans la manipulation de fonds.
