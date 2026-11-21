# Objectifs d'épargne

> Version 0.1 — 21 novembre 2026 — implémenté : `db/021_savings_goals.sql`, `apps/api/src/goals/`, carnet et écran du groupe dans l'app.

Chaque membre peut dire ce qu'il fera de la mise reçue à son tour : minerval, stock, toiture, moto… Un objectif clair aide à tenir jusqu'au bout de la rotation, et, s'il est partagé, rappelle aux autres pourquoi leur paiement compte.

## Règles

- **Un objectif par adhésion** (une tontine = un objectif). Types : `school`, `business`, `housing`, `health`, `family`, `equipment`, `other` ; un libellé libre (2 à 80 caractères) ; facultatifs : montant visé et date.
- **Personnel par défaut.** La table n'a pas de `group_id` : ses écritures vont dans la chaîne de journal du membre (`user:<uuid>`), jamais dans celle du groupe.
- **Partage choisi.** Avec `sharedWithGroup`, le type et le libellé apparaissent dans le tableau des tours, sous le tour du membre. Le montant visé reste privé.
- **Aucun solde.** La progression est calculée à chaque lecture : paiements **confirmés** reçus à mon tour, rapportés au montant visé (ou, sans montant, à la mise complète attendue : montant × (membres − 1)).
- Retirer un objectif le marque `archived_at` ; il reste dans le journal du membre.

## API

| Méthode | Chemin | Effet |
|---------|--------|-------|
| `GET` | `/groups/:id/goal` | `{ goal: {…} \| null }` |
| `PUT` | `/groups/:id/goal` | `{ kind, label, targetAmountMinor?, targetDate?, sharedWithGroup }` → crée ou remplace |
| `DELETE` | `/groups/:id/goal` | 204, retire l'objectif |

`GET /me/carnet` : chaque tontine porte `goal: { kind, label, targetAmountMinor, targetDate, sharedWithGroup, effectiveTargetMinor, progressMinor, progressPercent, reached } | null`.

`GET /groups/:id/cycles` : `beneficiary.goal: { kind, label } | null` (objectifs partagés seulement).
