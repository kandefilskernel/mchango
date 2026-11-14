# Achats groupés

« Avec ton groupe, achète moins cher. » Une boutique partenaire publie une offre à paliers ; les acheteurs réservent leur quantité ; à la date de fin, le prix est fixé au palier atteint ; chacun paie et retire en boutique. Mchango ne touche jamais l'argent : la boutique encaisse.

Plan et décisions : [`docs/plan-achats-groupes.md`](../docs/plan-achats-groupes.md). Schéma : [`db/019_achats.sql`](../db/019_achats.sql). API : `apps/api/src/purchases/`.

## Règles portées par la base

- **Compteur calculé** (vue `offer_progress`) : seules les commandes non annulées comptent. Un partage ne change rien.
- **Une commande par acheteur et par offre**, quel que soit le nombre de groupes ou de liens par lesquels l'offre est arrivée.
- **Offre figée une fois publiée** : ni prix, ni paliers, ni date de fin.
- **Prix final fixé par la base** à la clôture, au palier atteint ; une valeur fournie par l'appelant est ignorée. Sous le seuil minimum, l'offre ne peut qu'être annulée.
- **Chacun agit pour soi** : on ne réserve pas au nom d'un autre ; seul un employé actif de la boutique qui vend l'offre confirme un paiement ou un retrait.
- **Déclarer n'est pas payer** : la commande ne passe à « payée » qu'après confirmation par la boutique.
- **Journal** : une chaîne `offer:<uuid>` par offre (offre, paliers, partages, commandes, paiements, retraits). Boutiques et zones vont dans la chaîne de leur auteur (017).

## Cycles de vie

- Offre : `draft → open → closed → fulfilled`, ou `draft/open → cancelled`.
- Commande : `reserved → ready (code de retrait) → paid → picked_up` ; `reserved → cancelled` tant que l'offre est ouverte ; `ready → expired` après le délai de retrait fixé par la boutique.

Clôture, annulation sous le seuil, expiration et fin d'offre : tâche périodique (`PURCHASES_JOBS_ENABLED`, `PURCHASES_JOBS_INTERVAL_SECONDS`), écrite en `system`.

## Routes

JSON en camelCase, montants en unités mineures entières.

Sans compte :

| Route | |
|-------|-|
| `GET /zones` | Zones de retrait |
| `GET /offers?zoneId=` | Offres ouvertes, avec compteur et paliers |
| `GET /offers/:id` | Fiche d'une offre (jamais un brouillon, jamais un nom d'acheteur) |
| `GET /shares/:token` | Lien d'invitation → `{ offerId }` |

Acheteur (`AccessGuard`) :

| Route | |
|-------|-|
| `POST /offers/:id/orders` | Réserver : `quantity`, `pickupName`, `offlineId`, `shareToken` facultatif. Rejouable (même `offlineId`, même commande) |
| `PATCH /orders/:id` | Changer `quantity` ou `pickupName`, tant que l'offre est ouverte |
| `POST /orders/:id/cancel` | Annuler, tant que l'offre est ouverte |
| `POST /orders/:id/payments` | Déclarer un paiement : `method`, `txReference` hors espèces |
| `GET /me/orders` | Mes commandes : `amountDueMinor` après clôture, `indicativeTotalMinor` avant, `pickupCode` tant qu'il sert |
| `POST /offers/:id/shares` | Partager : `{ channel: 'whatsapp' }` (renvoie `token`) ou `{ channel: 'group', groupId }` ; `parentToken` pour l'origine |
| `GET /groups/:id/proposals` | Achats proposés à mon groupe : nombre de membres confirmés, jamais la liste des « sans réponse » |

Boutique (`AccessGuard` + employé actif de la boutique) :

| Route | |
|-------|-|
| `GET /me/merchants` | Mes boutiques |
| `GET /merchants/:id/offers` | Offres, brouillons compris |
| `POST /merchants/:id/offers` | Brouillon : `title`, `unitLabel`, `regularPriceMinor`, `endsAt`, `pickupWindowHours` (24 à 336), `tiers[{ minQuantity, unitPriceMinor }]` |
| `POST /merchants/:id/offers/:offerId/publish` | Publier |
| `POST /merchants/:id/offers/:offerId/cancel` | Retirer l'offre et annuler ses réservations |
| `GET /merchants/:id/orders?status=` | Commandes à encaisser et à remettre (`ready`, `paid` par défaut) |
| `POST /merchants/:id/orders/:orderId/confirm-payment` | Encaisser (confirme la déclaration, ou saisit le paiement au comptoir) |
| `POST /merchants/:id/orders/:orderId/confirm-pickup` | Remettre, sur présentation de `pickupCode` |

Erreurs : `400` entrée invalide, `401` pas de session, `403` pas le droit, `404` introuvable, `409` refus d'une règle de la base (son message est repris), `422` code de retrait incorrect.

## App mobile

Écrans dans `apps/mobile/lib/ui/purchases/`, client dans `apps/mobile/lib/api/purchases_api.dart`. Entrée « Achats groupés » en tête de l'accueil ; « Ma boutique » n'apparaît que pour les employés d'une boutique ; « Achats proposés » depuis l'écran d'un groupe.

## Pas encore fait

- Consulter les offres sans compte dans l'app (l'API le permet ; l'app demande d'abord la connexion).
- Lien WhatsApp qui ouvre directement l'offre (domaine web + liens d'app Android). Le partage est déjà enregistré pour l'origine des invitations.
- Création des boutiques, des employés et des zones depuis le back-office (aujourd'hui : en base).
- Groupes d'achat sans tontine.
- Rejet d'un paiement déclaré par la boutique ; lecture du journal d'une offre par ses participants ; limite de stock.
