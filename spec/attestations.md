# Attestation de régularité

> Version 0.1 — 21 novembre 2026 — implémenté : `db/022_attestations.sql`, `apps/api/src/attestations/`, écran « Attestation de régularité » dans l'app (menu de l'accueil et carnet).

Beaucoup de membres (marchandes, taxi-motards, artisans) n'ont aucun historique bancaire. Leurs cotisations dans Mchango, déclarées et confirmées par d'autres, sont une trace de sérieux. L'attestation leur permet de la montrer à qui ils veulent : IMF, coopec, bailleur, employeur.

## Ce que c'est, et ce que ce n'est pas

- Un **relevé de faits** figé à l'émission : paiements confirmés, à temps ou en retard, rejetés, tours reçus, tontines suivies et terminées, ancienneté, et, si le membre le choisit, les montants versés par devise.
- **Pas un score de crédit** ni une note : aucun calcul de « fiabilité » (le score de confiance reste un chantier V2, spec/categories.md).
- **Pas une garantie** : le texte le dit. Mchango ne prête, ne détient ni ne garantit rien.

## Émission et vérification

- Le membre émet une attestation (valable 30, 90 ou 180 jours ; 90 par défaut). Au plus 5 par jour. Il faut au moins un paiement confirmé.
- Le contenu est un JSON aux clés en ordre fixe, stocké tel quel ; son empreinte SHA-256 est vérifiée par la base (`CHECK`) et ne change plus (trigger). Seul le retrait (`revoked_at`) est possible.
- **Code de vérification** : 10 caractères sans 0/O, 1/I/L ni U (30^10 combinaisons), affiché `XXXXX-XXXXX`. QR : `MCHANGO-ATT1|<code>|<empreinte>`.
- Le numéro du titulaire est masqué (`+24397*****12`).
- **Vérification publique, sans compte** : `GET /attestations/:code` renvoie `status` (`valid`, `expired`, `revoked`), le contenu et l'empreinte. Une attestation retirée ne montre plus son contenu. 60 consultations par heure et par adresse IP.
- Journal : émission et retrait dans la chaîne du membre (`user:<uuid>`).

## API

| Méthode | Chemin | Effet |
|---------|--------|-------|
| `GET` | `/me/attestation-stats` | Les chiffres qui entreraient dans une attestation maintenant |
| `POST` | `/me/attestations` | `{ includeAmounts?, validDays? }` → 201 |
| `GET` | `/me/attestations` | Les 20 dernières |
| `POST` | `/me/attestations/:id/revoke` | Retrait |
| `GET` | `/attestations/:code` | Vérification publique |

## À faire ensuite

- Une page web de vérification (domaine à choisir) pour que l'IMF scanne le QR sans installer l'app.
- Faire relire le texte par un juriste (protection des données, consentement du membre).
