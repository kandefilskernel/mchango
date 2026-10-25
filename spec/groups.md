# Groupes et invitations : contrat de l'API

Implémentation : [`apps/api/src/groups/`](../apps/api/src/groups/). Tests : [`apps/api/test/groups.e2e-spec.ts`](../apps/api/test/groups.e2e-spec.ts).

Tous les points d'accès exigent `Authorization: Bearer <accessToken>` (voir [`auth.md`](auth.md)).

## Règles

- Le créateur d'un groupe en devient le **président**. Le groupe naît **en brouillon** (`draft`).
- Mode de versement : **direct au bénéficiaire** uniquement à l'itération 1.
- Seul le président crée des codes d'invitation, et seulement tant que le groupe est en brouillon.
- Rejoindre exige d'**accepter le règlement** (`rules_accepted_at` enregistré).
- Taille maximale fixée à la création (2 à 100, 30 par défaut). Vérifiée sous verrou : deux arrivées simultanées ne la dépassent pas.
- Un membre qui a quitté ou a été retiré ne revient pas par code : le président devra le réintégrer (pas encore implémenté).
- Les numéros de téléphone ne sont visibles que des membres du même groupe.
- La génération des tours et l'ordre de passage arrivent en semaine 2.

## Codes d'invitation

- Format `XXXX-XXXX`, 8 caractères parmi `23456789ABCDEFGHJKMNPQRSTVWXYZ` : pas de 0/O, 1/I/L, U. Un code se dicte et se recopie sans erreur.
- Saisie tolérante : minuscules, espaces et absence de tiret acceptés.
- Stocké en base sous forme d'empreinte HMAC (secret serveur). Le code n'apparaît **jamais** dans le journal.
- Validité 72 h par défaut (1 h à 14 jours), nombre d'utilisations illimité par défaut.
- 10 essais de code par utilisateur et par heure, contre le devinage.

## Points d'accès

### `POST /groups` → 201

```json
{
  "name": "Likelemba Kenya",
  "type": "informel",
  "currency": "CDF",
  "contributionAmountMinor": 20000,
  "frequency": "weekly",
  "startDate": "2026-11-02",
  "maxMembers": 30
}
```

- `contributionAmountMinor` : entier en unités mineures, **francs pour CDF, cents pour USD** (20 USD → `2000`).
- `frequency` : `daily`, `weekly` ou `monthly`.
- `startDate` : pas dans le passé (date du jour à Lubumbashi).
- `type` (défaut `informel`) et `maxMembers` (défaut 30) sont facultatifs.

Réponse : le groupe, avec `myRole: "president"` et `memberCount: 1`.

### `GET /groups` → 200

Les groupes dont je suis membre actif, du plus récent au plus ancien, avec `myRole` et `memberCount`.

### `GET /groups/:id` → 200

Détail et liste des membres (`membershipId`, `userId`, `fullName`, `phone`, `role`, `turnOrder`, `joinedAt`).
`404` si je ne suis pas membre : la réponse ne révèle pas si le groupe existe.

### `POST /groups/:id/invitations` → 201

```json
{ "validHours": 72, "maxUses": null }
```

Réponse :

```json
{
  "invitationId": "…",
  "code": "K7MP-Q2XW",
  "expiresAt": "2026-10-24T08:00:00.000Z",
  "maxUses": null,
  "shareText": "Rejoins notre tontine « Likelemba Kenya » sur Mchango avec le code K7MP-Q2XW (valable jusqu'au 24 octobre 2026 à 10:00)."
}
```

`shareText` est prêt à partager sur WhatsApp (heure de Lubumbashi).
Erreurs : `403` pas président, `404` pas membre, `409` groupe déjà démarré.

### `POST /groups/join` → 200

```json
{ "code": "k7mp q2xw", "acceptRules": true }
```

Réponse : `{ "groupId": "…" }`.
Erreurs :
- `400` règlement non accepté ;
- `404` code invalide ou expiré ;
- `409` déjà membre, code épuisé, groupe complet ou déjà démarré ;
- `403` membre ayant quitté ou été retiré ;
- `429` trop d'essais.

## Signature du règlement (avant le démarrage)

Chaque membre **signe le règlement** avant que le président puisse démarrer. Ainsi personne ne peut dire ensuite qu'il n'était pas d'accord avec le montant, la date ou son tour.

- **Le règlement signé** est résumé par une empreinte SHA-256 (`terms_hash`) d'un texte canonique : JSON aux clés triées, avec `amount_minor`, `currency`, `frequency`, `group_id`, `order` (liste `[tour, membership_id]` dans l'ordre des tours), `payout_mode`, `start_date` et `version: "mchango-terms-v1"` (`apps/api/src/groups/terms.ts`).
- **Rien à signer** tant que l'ordre des tours n'est pas fixé pour tous (au moins 2 membres).
- **`GET /groups/:id`** renvoie `terms: { hash, ready, signedBy, missing, allSigned }` tant que le groupe est en préparation, puis `null`.
- **`POST /groups/:id/sign`** `{ "termsHash": "…" }` : le membre signe le règlement qu'il a lu. Signer deux fois ne change rien. Erreurs `409` : règlement changé entre-temps (« relisez-le »), pas encore complet, ou groupe déjà démarré. `404` pour un non-membre.
- **Tout changement** (ordre des tours, montant, fréquence, date) change l'empreinte : les signatures précédentes ne comptent plus et il faut re-signer. Elles restent en base (`group_terms_signatures`, ajout seul).
- **`POST /groups/:id/start`** refuse (`409`) tant que tous les membres actifs n'ont pas signé le règlement actuel, et nomme ceux qui manquent.
- **Dans l'app :** la signature est confirmée par le **PIN** (ou l'empreinte), vérifié sur le téléphone, avec la même pause que pour l'ouverture après 5 PIN faux. La session reste signée par la clé du téléphone.
- **À vérifier avec un juriste :** la valeur de cette signature électronique en droit congolais (Code du numérique), en cas de conflit porté devant un tribunal.

## Journal (chaîne du groupe)

- `group.terms_signed` : membre, empreinte du règlement, version (une ligne par signature) ;
- `groups.insert` ;
- `memberships.insert` : un par adhésion, attribué au membre qui rejoint ;
- `group.invitation_created` : identifiant, expiration et nombre d'utilisations, **sans le code**.
