# Journal d'audit : format du hash (`mchango-v1`)

Référence d'implémentation : `audit_hash()` dans [`db/001_schema.sql`](../db/001_schema.sql).
Toute implémentation (Dart, TypeScript…) doit passer les vecteurs de [`test-vectors/audit_chain.json`](test-vectors/audit_chain.json).

## Chaînes

- Une chaîne par groupe : `chain_id = "group:<uuid>"` ; une chaîne `"global"` pour le reste.
- `seq` commence à 1 et augmente de 1, sans trou.
- Le premier événement a `prev_hash` = 64 caractères `0`.
- Chaque événement a `prev_hash` = `hash` de l'événement précédent.

## Calcul du hash

```
hash = hex_minuscule( SHA-256( UTF-8( join("\n", champs) ) ) )
```

Les champs, **dans cet ordre** :

| # | Champ | Valeur |
|---|-------|--------|
| 1 | version | la chaîne littérale `mchango-v1` |
| 2 | `chain_id` | tel quel |
| 3 | `seq` | entier en décimal, sans zéros devant |
| 4 | `prev_hash` | 64 caractères hexadécimaux minuscules |
| 5 | `actor_type` | `user`, `staff` ou `system` |
| 6 | `actor_id` | UUID en minuscules, ou chaîne vide si absent |
| 7 | `device_id` | UUID en minuscules, ou chaîne vide si absent |
| 8 | `action` | tel quel |
| 9 | `created_at` | UTC, exactement `YYYY-MM-DDTHH:MM:SS.mmmZ` (millisecondes sur 3 chiffres) |
| 10 | `payload` | le texte JSON **tel que stocké**, octet pour octet, sans le réinterpréter |
| 11 | `signature` | base64, ou chaîne vide si absente |

## Règles pour l'API et les clients

- L'API renvoie `created_at` et `payload` sous forme de **chaînes**, exactement comme ci-dessus. Le client ne doit ni reparser ni reformater `payload` avant de hacher.
- `payload` ne contient jamais de saut de ligne brut (contrainte en base) ; le séparateur `\n` n'est donc pas ambigu.
- Le client mémorise le dernier `(seq, hash)` vérifié pour chaque groupe. Si le serveur renvoie plus tard un historique où ce `seq` a un autre hash, l'historique a été réécrit : alerte.

## Régénérer les vecteurs

Voir [`tools/README.md`](tools/README.md).
