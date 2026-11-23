# Part du président

> Version 0.1 — 23 novembre 2026 — implémenté : `db/025_president_fee.sql`, `apps/api/src/contributions/president-fees.service.ts`, écrans de création, de modification, de signature et de tour dans l'app.

Le président d'une tontine fait un vrai travail : il réunit les membres, relance les retards, arbitre. Il peut recevoir une **part de chaque mise**, discutée avec les membres.

## Règles

- **De 0 à 10 %** de la mise d'un tour (la mise = montant × (membres − 1)). Par défaut : 0, pas de part.
- **Discutée avec les membres, acceptée par chacun** : le pourcentage fait partie du **règlement signé**. Le changer avant le démarrage annule les signatures ; chacun doit signer de nouveau. Il apparaît aussi dans l'aperçu avant de rejoindre.
- **Figée au démarrage** : la base refuse tout changement après (trigger `groups_lock_president_fee`).
- **Qui paie** : le bénéficiaire de chaque tour, sur la mise qu'il reçoit. Les autres membres paient toujours le même montant. **Au tour du président, il n'y a rien à payer.**
- **Montant** : arrondi vers le bas, en unités mineures. Exemple : 3 membres, 20 000 FC, 5 % → mise de 40 000 FC, part de 2 000 FC.
- **Double regard, comme une cotisation** : le bénéficiaire paie le président hors de Mchango (mobile money ou en main), puis déclare « J'ai payé le président » ; le président confirme « J'ai reçu » ou signale un problème avec un motif.
- **Un numéro de transaction ne sert qu'une fois**, cotisations et parts du président confondues (contrôle à l'enregistrement d'une part).
- **La base vérifie** que le payeur est le bénéficiaire du tour, que le receveur est le président, et que le montant est exactement celui du règlement.
- **Journal du groupe** : la déclaration et la décision y sont inscrites, visibles de tous les membres.

> **Mchango ne touche jamais cet argent**, comme pour les cotisations. Il enregistre une déclaration et une confirmation entre deux membres. À faire confirmer par le juriste avec le reste du modèle : une commission entre membres, librement acceptée, n'est pas une rémunération de Mchango.

## API

| Méthode | Chemin | Qui | Effet |
|---|---|---|---|
| `POST` | `/groups` | président | `presidentFeeBps` (0 à 1000 ; 500 = 5 %), 0 par défaut |
| `PATCH` | `/groups/:id` | président, avant le démarrage | `presidentFeeBps` ; après le démarrage : 409 |
| `GET` | `/groups/:id/cycles/:n` | membre | `presidentFee: { bps, amountMinor, payerMembershipId, presidentMembershipId, payment } \| null` |
| `POST` | `/groups/:id/cycles/:n/president-fee` | bénéficiaire du tour | `{ method, txReference?, offlineId }` → 201 ; rejouable avec le même `offlineId` |
| `POST` | `/president-fees/:id/decisions` | président | `{ decision: 'confirm' \| 'dispute', note? }` (motif obligatoire pour `dispute`) |

`presidentFeeBps` est aussi renvoyé par `GET /groups/:id` et par l'aperçu d'invitation (`POST /groups/preview`).

## Pas encore fait

- Rappel SMS de la part du président au bénéficiaire.
- Ligne « part du président » dans le carnet et dans l'attestation de régularité.
- Rejet d'une part par l'équipe Mchango (comme pour les litiges de cotisation).
