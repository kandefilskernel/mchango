# Rappels avant échéance

Implémentation : [`apps/api/src/reminders/`](../apps/api/src/reminders/). Tests : [`apps/api/test/reminders.e2e-spec.ts`](../apps/api/test/reminders.e2e-spec.ts).

Périmètre du document de cadrage pour l'itération 1 : **un seul canal, un rappel avant échéance**. Le canal est le SMS, le seul déjà branché. WhatsApp demandera l'API WhatsApp Business et l'approbation de modèles de messages par Meta.

## Règles

| Règle | Valeur |
|-------|--------|
| Qui | Les membres actifs qui doivent payer ce tour et **n'ont pas encore déclaré** (déclaration non rejetée). Jamais le bénéficiaire du tour. |
| Quand | Hebdomadaire et mensuelle : **la veille** de l'échéance. Quotidienne : **le matin même**. |
| Heures d'envoi | De 8 h à 20 h, heure de Lubumbashi. Pas de SMS la nuit : un tour qui tombe la nuit attend 8 h. |
| Combien | **Un rappel par membre et par tour**, garanti par la base (`notifications.dedupe_key` unique, réservée avant l'envoi). Vrai même avec plusieurs serveurs. |
| Fréquence de vérification | Toutes les 15 minutes (`REMINDERS_INTERVAL_MINUTES`). `REMINDERS_ENABLED=0` désactive. |
| Échec d'envoi | Noté `failed` avec l'erreur dans `notifications`. **Pas de nouvel essai automatique** au MVP. |

## Texte

> Mchango : Kwetu, tour 3. Payez 20 000 FC à Mama Furaha (+243991234567) d'ici le 02/11/2026, puis déclarez-le dans l'app.

Le texte dit **qui payer, combien, à quel numéro et quand**, puis rappelle de déclarer.

## Coût : un SMS, pas trois

Un SMS fait 160 caractères **seulement en alphabet GSM-7**. Un seul caractère hors de cet alphabet (`ê`, `ç`, `«`, `’`, un emoji…) fait passer tout le message en UCS-2 : 70 caractères par SMS, donc 2 ou 3 SMS facturés.

- `toGsm7()` remplace ces caractères. Les accents courants `é è à ù` font partie de GSM-7 et restent.
- Les noms de groupe et de bénéficiaire sont tronqués (20 et 18 caractères).
- Un test vérifie le pire cas (noms longs et accentués, montant maximal, tour 100) : **un seul SMS**.
- Le SMS du code de connexion a été réécrit pour la même raison : il contenait « même ».

## Limites

- **Pas encore de vrai fournisseur SMS** (`SMS_DRIVER=console`, interdit en production). À choisir et à tester en RDC : couverture Vodacom, Airtel, Orange et Africell, délivrabilité, prix par SMS, identifiant d'expéditeur « Mchango ».
- **Coût à budgéter** : environ 1 SMS par membre et par tour, plus les codes de connexion.
- Pas de rappel aux bénéficiaires qui ont des paiements à confirmer, ni de relance après l'échéance : à décider après le pilote.
