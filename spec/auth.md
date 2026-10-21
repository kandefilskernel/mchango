# Authentification : contrat de l'API

Implémentation : [`apps/api/src/auth/`](../apps/api/src/auth/). Tests : [`apps/api/test/auth.e2e-spec.ts`](../apps/api/test/auth.e2e-spec.ts).

## Principes

| Facteur | Rôle |
|---------|------|
| **Code SMS** (6 chiffres, 5 min, 5 essais) | Prouve la possession du numéro. |
| **PIN** (6 chiffres) | Vérifié par le serveur **seulement** pour lier un nouveau téléphone. 5 échecs → bloqué 30 min. |
| **Clé de l'appareil** (Ed25519) | Générée par l'app, clé privée dans le stockage sécurisé Android, jamais envoyée. Sert à ouvrir chaque session. |

- **Un vol de carte SIM seul ne suffit pas** : lier un nouveau téléphone demande le code SMS **et** le PIN.
- **Un seul appareil actif par compte** au MVP : lier un nouveau téléphone révoque l'ancien, et c'est journalisé.
- Le PIN sert aussi à **déverrouiller l'app en local** (semaine 3, côté Flutter) ; il ne transite pas à chaque connexion.
- Pas de jeton de rafraîchissement : quand le jeton d'accès (15 min) expire, l'app signe un nouveau défi.

## Parcours

```
Inscription           Nouveau téléphone         Ouverture de l'app
-----------           -----------------         ------------------
otp/request           otp/request               challenge
otp/verify            otp/verify                (signature locale)
  accountExists=false   accountExists=true      session → accessToken
register → session    devices (PIN) → session
```

## Points d'accès

Toutes les erreurs ont la forme `{ "message": "...", "statusCode": n }` (messages en français, affichables tels quels).

### `POST /auth/otp/request` → 202

```json
{ "phone": "0991234567" }
```

Formats acceptés : `0991234567`, `991234567`, `243991234567`, `00243…`, `+243 99 123 4567`. Le serveur normalise en `+243991234567`.
Erreurs : `400` numéro invalide, `429` plus de 3 codes en 15 min pour ce numéro.

### `POST /auth/otp/verify` → 200

```json
{ "phone": "0991234567", "code": "205412" }
```

Réponse : `{ "otpToken": "…", "accountExists": false }`. `otpToken` vaut 10 min et ne sert qu'**une fois** (consommé seulement quand l'inscription ou la liaison réussit).
Erreurs : `401` code faux, expiré ou déjà utilisé.

### `POST /auth/register` → 201

```json
{
  "otpToken": "…",
  "fullName": "Mama Furaha",
  "pin": "482915",
  "devicePublicKey": "<32 octets Ed25519, base64 standard>",
  "language": "fr"
}
```

Réponse (session) : `{ "userId", "deviceId", "accessToken", "expiresIn": 900 }`. L'app **doit conserver `deviceId`**.
Erreurs : `400` PIN faible (chiffre répété, suite) ou clé invalide, `401` vérification expirée/utilisée, `409` compte existant ou clé déjà liée.

### `POST /auth/devices` → 201

```json
{ "otpToken": "…", "pin": "482915", "devicePublicKey": "…" }
```

Réponse : session. Révoque l'appareil précédent.
Erreurs : `401` PIN faux (message avec les essais restants), `423` PIN bloqué (`lockedUntil` en ISO 8601), `404` pas de compte, `403` compte bloqué.

### `POST /auth/challenge` → 200

```json
{ "deviceId": "…" }
```

Réponse : `{ "nonce": "…", "expiresIn": 120 }`. Répond même pour un appareil inconnu (ne révèle rien).

### `POST /auth/session` → 200

```json
{ "deviceId": "…", "nonce": "…", "signature": "<Ed25519, base64>" }
```

Le message signé est exactement (UTF-8, séparateur `\n`) :

```
mchango-auth-v1
<deviceId>
<nonce>
```

Réponse : session. Un défi ne sert qu'une fois.
Erreurs : `401` défi inconnu/expiré/rejoué, signature fausse ou appareil révoqué, `403` compte bloqué.

### `GET /me` → 200

En-tête `Authorization: Bearer <accessToken>`. Réponse : `{ "id", "phone", "full_name", "language", "deviceId" }`.

## Journal

Dans la chaîne `global` : `auth.user_registered`, `auth.device_linked` (avec `revoked_device_ids`), `auth.pin_locked`. Le PIN, son hash et les codes SMS n'y figurent jamais.

## Limites connues

- Un appareil révoqué garde l'accès jusqu'à l'expiration de son jeton (15 min au plus).
- Le fournisseur SMS réel n'est pas branché (`SMS_DRIVER=console`, interdit en production).
- Limite par IP volontairement haute (200/h) : les opérateurs mobiles partagent souvent une IP entre beaucoup d'abonnés (CGNAT). À ajuster avec les chiffres réels du pilote.
- PIN oublié : avec la confirmation d'un garant de la tontine, voir [`pin-reset.md`](pin-reset.md). Pas encore de recours par le support si aucun garant ne répond.
