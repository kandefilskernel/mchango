# « PIN oublié »

Implémentation :
- API : [`apps/api/src/auth/pin-reset.service.ts`](../apps/api/src/auth/pin-reset.service.ts) ;
- app : `lib/ui/auth/pending_reset_screen.dart`, `lib/ui/groups/approvals_screen.dart`.

Tests : [`apps/api/test/pin-reset.e2e-spec.ts`](../apps/api/test/pin-reset.e2e-spec.ts), `apps/mobile/test/pin_reset_test.dart`.

## Le problème

Le PIN protège contre le **vol de carte SIM** : celui qui récupère un numéro reçoit ses codes SMS. Si « PIN oublié » marchait avec le seul code SMS, voler la carte SIM suffirait à prendre le compte. La récupération demande donc **une personne qui connaît le demandeur**.

## Règle

| Situation du demandeur | Ce qu'il faut |
|------------------------|---------------|
| Membre d'au moins une tontine en préparation ou en cours | Code SMS **et** confirmation d'un **garant** |
| Aucune tontine en préparation ou en cours | Code SMS seul : aucun argent en jeu, le compte est vide |

**Garants** : dans chaque tontine en préparation ou en cours du demandeur, le **président**. Si le demandeur est lui-même président, ce sont les **autres membres**.

## Parcours

1. App : numéro → code SMS → « PIN oublié ? » → nouveau PIN (deux fois).
2. L'API enregistre la demande : empreinte argon2 du nouveau PIN, clé du nouveau téléphone, expiration à **48 h**. Une nouvelle demande annule la précédente.
3. Les garants (3 au plus) reçoivent un SMS **sur leur propre numéro**, que le voleur ne contrôle pas : « X demande un nouveau PIN. Confirmez dans l'app seulement si vous lui avez parlé de vive voix. »
4. Le garant voit un bandeau sur son accueil. Avant de confirmer, l'app l'avertit : confirmer pour quelqu'un qui a pris le numéro lui donnerait le compte.
5. Une fois confirmé :
   - le nouveau PIN est actif et le verrouillage remis à zéro ;
   - **tous les anciens téléphones sont déconnectés** ;
   - le nouveau téléphone est lié ;
   - l'événement entre dans le **journal du groupe** du garant (`auth.pin_reset_approved`), visible de tous les membres, et dans la chaîne `global` (`auth.pin_reset_completed`).
6. Le demandeur touche « vérifier » : son téléphone ouvre sa session avec sa clé (défi signé), comme d'habitude.

Un refus (`auth.pin_reset_rejected`, aussi dans le journal du groupe) ne change rien : l'ancien PIN reste valable.

## Points d'accès

| Méthode | Chemin | Qui | Effet |
|---------|--------|-----|-------|
| `POST` | `/auth/pin-reset` | demandeur (sans session) | `{ otpToken, newPin, devicePublicKey }` → `pending` (avec la liste des garants) ou `completed` (avec la session) |
| `GET` | `/auth/pin-reset/:id` | demandeur | `pending`, `completed` (avec `deviceId`), `rejected`, `cancelled` ou `expired`. L'identifiant aléatoire suffit : la réponse ne contient rien de secret. |
| `GET` | `/pin-resets/pending` | garant connecté | demandes qu'il peut confirmer |
| `POST` | `/pin-resets/:id/approve` | garant connecté | applique la demande |
| `POST` | `/pin-resets/:id/reject` | garant connecté | refuse la demande |

Un utilisateur qui n'est pas garant d'une demande reçoit `404` : il ne voit pas les demandes des autres.

## Limites honnêtes

- **Le garant peut être trompé.** Un voleur de carte SIM peut appeler le président depuis le bon numéro. D'où la consigne « de vive voix », l'avertissement dans l'app, le journal visible de tout le groupe, et la déconnexion de l'ancien téléphone : le vrai titulaire s'en aperçoit.
- **Si aucun garant ne répond**, la demande expire. Il n'y a pas encore de recours par le support : il faudra une procédure avec vérification d'identité au back-office.
- **Une tontine qui démarre** pendant qu'une demande est en attente peut changer la liste des garants. C'est sans risque : les garants sont recalculés à chaque confirmation.
