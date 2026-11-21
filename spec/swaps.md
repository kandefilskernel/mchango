# Échange de tour entre deux membres

> Version 0.1 — 21 novembre 2026 — implémenté : `db/020_turn_swaps.sql`, `apps/api/src/swaps/`, écran du groupe dans l'app.

Dans une likelemba, un membre qui a une urgence (deuil, minerval, loyer, maladie) demande souvent à un autre d'échanger leurs places. Mchango rend cet arrangement explicite, consenti et visible.

## Règles

- **Deux accords.** Le demandeur propose, le membre sollicité accepte ou refuse. Personne d'autre (ni le président, ni l'équipe Mchango) ne peut accepter à sa place.
- **Les dates ne bougent pas.** Seuls les bénéficiaires des deux tours sont échangés : chacun reçoit à la date de l'autre. Les autres membres paient le même montant aux mêmes dates ; seul le destinataire de deux tours change.
- **Pas après le premier paiement.** Un tour terminé, ou pour lequel un paiement est déclaré (et pas rejeté), ne s'échange plus : l'argent est déjà parti vers l'ancien bénéficiaire. La base le refuse elle-même (trigger `cycles_guard_beneficiary`).
- **Le bénéficiaire d'un tour ne change que par un échange accepté** dans la même transaction (même trigger) : ni l'API ni un script ne peuvent modifier un tour autrement.
- **Une demande en attente par membre et par groupe.** Elle expire après 72 h sans réponse : le silence ne vaut pas accord.
- Quand un échange est accepté, les autres demandes en attente des deux membres sont annulées (leurs tours ont changé).
- **Journal du groupe.** La demande, la réponse et le changement des deux tours sont des événements de la chaîne du groupe, visibles de tous.
- Le règlement signé (`terms_hash`) reste celui du démarrage : l'échange est un accord ultérieur entre deux membres, inscrit au journal.

> Le cadrage (§2) demande la majorité pour une modification des **règles** en cours de cycle. Un échange ne change ni le montant, ni les dates, ni la place des autres : seul l'accord des deux intéressés est requis. À confirmer pendant le pilote ; si des groupes veulent un accord du président, ce sera un réglage du groupe.

## API

| Méthode | Chemin | Qui | Effet |
|---------|--------|-----|-------|
| `GET` | `/groups/:id/swaps` | membre | Les 50 dernières demandes du groupe |
| `POST` | `/groups/:id/swaps` | membre | `{ targetMembershipId, reason? }` → 201, demande `pending` |
| `POST` | `/swaps/:id/accept` | membre sollicité | Échange les deux bénéficiaires → 200 |
| `POST` | `/swaps/:id/decline` | membre sollicité | → 200 |
| `POST` | `/swaps/:id/cancel` | demandeur | → 200 |

Une demande : `{ id, groupId, requester: { membershipId, fullName }, target: {…}, requesterCycleNumber, targetCycleNumber, reason, status, createdAt, expiresAt, decidedAt }`. `status` vaut `pending`, `accepted`, `declined`, `cancelled` ou `expired` (calculé : en attente et échue).

Erreurs : 409 si le groupe n'est pas en cours, si l'un des tours est passé ou a déjà un paiement déclaré, si une demande est déjà en attente, si la demande a expiré ou déjà reçu une réponse ; 403 si ce n'est pas au bon membre de répondre.

`GET /groups/:id/cycles` donne pour chaque tour `declaredCount` (paiements déclarés, confirmés ou non) : l'app ne propose l'échange que pour des tours à 0.

Après un échange, `GET /groups/:id` renvoie pour chaque membre son tour actuel (celui du tableau des tours), et plus l'ordre signé au démarrage.
