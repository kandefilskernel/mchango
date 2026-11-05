# Reçus et historique : contrat de l'API

Tests : [`apps/api/test/cycles.e2e-spec.ts`](../apps/api/test/cycles.e2e-spec.ts).

## `GET /contributions/:id/receipt` → 200

Réservé aux membres du groupe (`404` sinon). `409` tant que la cotisation n'est pas confirmée.

```json
{
  "receiptNumber": "MCH-00000042",
  "contributionId": "…",
  "groupId": "…",
  "groupName": "Likelemba Kenya",
  "cycleNumber": 1,
  "dueDate": "2026-11-02",
  "currency": "CDF",
  "amountMinor": 20000,
  "method": "airtel",
  "txReference": "AM12345678",
  "isLate": false,
  "payer": { "fullName": "Papa Jean", "phone": "+243…" },
  "beneficiary": { "fullName": "Mama Furaha", "phone": "+243…" },
  "witness": null,
  "declaredAt": "2026-10-21T09:00:00.000Z",
  "confirmedAt": "2026-10-21T09:05:00.000Z",
  "audit": { "chainId": "group:…", "seq": 17, "hash": "…" },
  "qrPayload": "MCHANGO1|MCH-00000042|<contributionId>|<groupId>|17|<hash>"
}
```

- **Numéro** : attribué par une séquence au moment où la cotisation passe `confirmed`, dans la même écriture. Il est donc dans le journal (`contributions.update`, champ `receipt_number`).
- **`audit`** : l'événement du journal qui a confirmé la cotisation.
- **Contenu du QR**, séparé par `|` : version `MCHANGO1`, numéro du reçu, identifiant de la cotisation, identifiant du groupe, `seq` et `hash` de l'événement de confirmation. Vérifier un reçu en V2 = retrouver cet événement dans la chaîne du groupe et vérifier la chaîne.
- Le reçu atteste un **accord enregistré** (déclaration + confirmation), pas un transfert garanti par Mchango.

## `GET /groups/:id/history?afterSeq=0&limit=500` → 200

Réservé aux membres. Les événements de la chaîne du groupe, dans l'ordre, au format exact de [`audit-hash.md`](audit-hash.md) :
- champs hachés : `chain_id`, `seq`, `prev_hash`, `actor_type`, `actor_id`, `device_id`, `action`, `created_at`, `payload`, `signature`, `hash` ;
- en plus, pour l'affichage seulement : `actor_name`.

Pagination : `afterSeq` = dernier `seq` reçu ; page de 500 au plus.

## `POST /groups/preview` → 200

```json
{ "code": "k7mp-q2xw" }
```

Aperçu avant de rejoindre : `name`, `type`, `currency`, `contributionAmountMinor`, `frequency`, `payoutMode`, `startDate`, `status`, `maxMembers`, `memberCount`, `presidentName`.
Compte dans la limite de 10 essais de code par heure. `404` si le code est invalide, expiré ou épuisé.
