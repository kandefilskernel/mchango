# Tirage de l'ordre des tours (`mchango-draw-v1`)

Implémentation : [`apps/api/src/groups/draw.ts`](../apps/api/src/groups/draw.ts). Vecteurs communs : [`test-vectors/draw.json`](test-vectors/draw.json), calculés par une implémentation Python indépendante.

## Ce que le tirage garantit

- **Le président ne choisit pas le résultat.** Le serveur tire une graine aléatoire de 32 octets ; le président déclenche le tirage, mais ne fournit rien qui l'influence.
- **Chacun peut refaire le calcul.** La graine, la liste des membres et l'ordre obtenu sont publiés dans le journal du groupe (`group.turn_order_set`), et la graine est renvoyée par `GET /groups/:id` (`drawSeed`).
- **Pas de tirage à répétition.** Un seul tirage par liste de membres. Il ne redevient possible que si la liste change (un nouveau membre). Passer à un ordre choisi ne débloque pas un nouveau tirage, et la graine du tirage remplacé reste visible.

## Limite honnête

C'est le **serveur** qui tire la graine. Un membre peut vérifier que l'ordre publié découle bien de la graine publiée, mais pas que Mchango n'a pas choisi une graine arrangeante. La confiance repose donc sur Mchango, qui n'a aucun intérêt dans l'ordre d'un groupe.

Pour s'en passer (V2 éventuelle), chaque membre engagerait un secret (hash publié), puis les secrets révélés seraient combinés en graine : personne, ni Mchango ni un membre, ne contrôlerait seul le résultat.

## Algorithme

Entrées : `seed` (64 caractères hex = 32 octets) et la liste des identifiants d'adhésion (UUID).

1. Mettre les UUID en minuscules et les **trier** par comparaison de caractères (ordre des codes, pas un tri dépendant de la langue).
2. Mélange de Fisher-Yates, pour `i` de `n - 1` jusqu'à `1` :
   - `mac = HMAC-SHA256(clé = seed (octets), message = "mchango-draw-v1:" + i)` ; `i` en décimal, en UTF-8 ;
   - `j = (8 premiers octets de mac, entier non signé big-endian) mod (i + 1)` ;
   - échanger les positions `i` et `j`.
3. Le résultat est l'ordre de passage : le premier élément reçoit au tour 1.

Biais du modulo : au plus 100 / 2^64, négligeable.

Empreinte des membres (`members_hash`) : SHA-256 hex des UUID triés (étape 1), joints par `\n`.
