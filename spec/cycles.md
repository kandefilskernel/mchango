# Tours, cycles et cotisations : contrat de l'API

Implémentation :
- [`apps/api/src/groups/lifecycle.service.ts`](../apps/api/src/groups/lifecycle.service.ts) : ordre des tours, démarrage ;
- [`apps/api/src/contributions/`](../apps/api/src/contributions/) : tableau des tours, déclaration, confirmation.

Tests : [`apps/api/test/cycles.e2e-spec.ts`](../apps/api/test/cycles.e2e-spec.ts).

Tous les points d'accès exigent `Authorization: Bearer <accessToken>`. Un non-membre reçoit `404`.

## Vue d'ensemble

```
Brouillon (président)                      Groupe actif (membres)
---------------------                      ----------------------
PATCH  /groups/:id           corriger      GET  /groups/:id/cycles             tableau des tours
PUT    /groups/:id/turn-order   ordre choisi  GET  /groups/:id/cycles/:n          détail d'un tour
POST   /groups/:id/turn-order/draw  tirage    POST /groups/:id/cycles/:n/contributions   « j'ai payé »
POST   /groups/:id/start     démarrer      POST /contributions/:id/decisions   confirmer / témoigner / contester
```

MVP : **un groupe = une rotation** (N membres → N tours, chacun reçoit une fois). Pour une nouvelle rotation, on crée un nouveau groupe.

## Préparation (président, groupe en brouillon)

### `PATCH /groups/:id` → 200

Champs modifiables, tous facultatifs : `name`, `contributionAmountMinor`, `frequency`, `startDate`, `maxMembers`. La devise et le type ne changent pas.
Erreurs : `403` pas président, `409` groupe démarré ou plus de membres que le nouveau maximum.

### `PUT /groups/:id/turn-order` → 200 (ordre choisi)

```json
{ "membershipIds": ["<tour 1>", "<tour 2>", "…"] }
```

La liste doit contenir **chaque membre actif une seule fois** (`400` sinon).
Réponse : `{ "mode": "chosen", "order": [{ "turn": 1, "membershipId", "fullName" }, …] }`.

### `POST /groups/:id/turn-order/draw` → 200 (tirage)

Réponse : `{ "mode": "draw", "algorithm": "mchango-draw-v1", "seed", "membersHash", "order": […] }`.
`409` si un tirage a déjà eu lieu pour exactement ces membres. Voir [`draw.md`](draw.md).

### `POST /groups/:id/start` → 200

- Exige au moins 2 membres, chacun avec un tour (1 à N), et une date de début qui n'est pas passée (`409` sinon).
- Crée un cycle par membre. Échéance du tour `k` = date de début + `(k − 1)` jours, semaines ou mois. En mensuel, le calcul part toujours de la date de début : 31 janvier → 28/29 février → 31 mars.
- Le tour 1 est `open`, les autres `upcoming`. Le groupe passe `active`, les codes d'invitation sont révoqués, et l'ordre des tours est figé (imposé par la base).

## Pendant la rotation

### `GET /groups/:id/cycles` → 200

```json
{
  "myMembershipId": "…",
  "cycles": [
    { "cycleNumber": 1, "dueDate": "2026-11-02", "status": "open",
      "beneficiary": { "membershipId": "…", "fullName": "Mama Furaha" },
      "confirmedCount": 1, "expectedCount": 2 }
  ]
}
```

### `GET /groups/:id/cycles/:n` → 200

Pour chaque membre qui doit payer ce tour (tous sauf le bénéficiaire) :

| `status` | Sens |
|----------|------|
| `expected` | Pas encore déclaré, échéance pas passée |
| `late` | Pas encore déclaré, échéance passée (date de Lubumbashi) |
| `declared` | Déclaré, en attente de confirmation |
| `disputed` | Contesté |
| `confirmed` | Confirmé |

Avec `contribution` (détail de la déclaration ou `null`) et `decisions` (qui a répondu, quoi, quand).

### `POST /groups/:id/cycles/:n/contributions` → 201

```json
{
  "method": "mpesa",
  "txReference": "RK45TX9QPL",
  "amountMinor": 20000,
  "offlineId": "<uuid généré par l'app>"
}
```

- Le payeur est l'utilisateur connecté ; le receveur est **le bénéficiaire du tour** (mode direct, imposé par la base).
- `amountMinor` doit être **exactement** le montant du groupe : le paiement partiel arrive en V2.
- `mpesa`, `airtel`, `orange`, `other` : `txReference` obligatoire, 5 à 30 lettres, chiffres, `.` ou `-`. Normalisé en majuscules sans espaces. Les formats réels des opérateurs restent à vérifier sur de vrais SMS.
- `cash` : `witnessMembershipId` obligatoire, un autre membre actif, ni le payeur ni le bénéficiaire.
- `offlineId` : renvoyer la même déclaration (réseau coupé, nouvel essai) rend la déclaration existante avec `replayed: true`, sans doublon.
- `isLate` vaut `true` si la déclaration arrive après l'échéance.

Erreurs :
- `400` bénéficiaire qui cotise, mauvais montant, ID manquant, témoin invalide ;
- `404` tour inexistant ;
- `409` groupe non démarré ou terminé, tour clos, **ID de transaction déjà utilisé** (tous groupes confondus), déjà déclaré pour ce tour.

### `POST /contributions/:id/decisions` → 200

```json
{ "decision": "confirm" }
{ "decision": "witness" }
{ "decision": "dispute", "note": "Je n'ai rien reçu" }
```

| Décision | Qui | Effet |
|----------|-----|-------|
| `confirm` | le bénéficiaire seulement | Mobile money : confirmée. Espèces : il faut aussi le témoin. |
| `witness` | le témoin désigné, espèces seulement | Espèces : confirmée si le bénéficiaire a aussi confirmé. |
| `dispute` | tout membre sauf le payeur, motif obligatoire | Statut `disputed`, litige ouvert. Une confirmation ultérieure du bénéficiaire le clôt (`resolved_confirmed`). |

Réponse : la cotisation, plus `cycleStatus` (`open` ou `completed`) quand elle vient d'être confirmée.
Quand tous les payeurs d'un tour sont confirmés, le tour passe `completed` et le suivant `open`. Après le dernier tour, le groupe passe `closed`.

Erreurs : `403` mauvaise personne, `409` déjà répondu ou cotisation déjà confirmée.

## Mon carnet (`GET /me/carnet`)

Résumé personnel, toutes tontines confondues, pour le membre connecté :

- `totals` : par devise (les francs et les dollars ne s'additionnent pas), le total **versé** et le total **reçu**, en comptant seulement les paiements **confirmés** par le bénéficiaire ;
- `upcoming` : les prochaines étapes, par date. `pay` est le premier tour non payé de chaque tontine en cours, avec le bénéficiaire et `late` si l'échéance est passée. `receive` est mon tour, avec le montant attendu (cotisation × membres moins un) ;
- `groups` : par tontine, mon tour, versé et reçu (nombre et montant), déclarations en attente de confirmation.

Ce sont des montants constatés entre membres, pas un solde : Mchango ne détient aucun fonds.

## Journal (chaîne du groupe)

`groups.update`, `memberships.update` (ordre), `group.turn_order_set` (mode, ordre ; graine et empreinte pour un tirage), `cycles.insert`, `contributions.insert/update`, `confirmations.insert`, `disputes.insert/update`. Chaque événement porte son auteur.

## Pas encore fait

- Litige qui se termine par un rejet, puis nouvelle déclaration du payeur (la base l'autorise, l'API pas encore).
- Médiation par le président ou l'équipe.
- Paiement partiel, pénalités de retard (V2).
- Reçus avec QR code (semaine 3).
