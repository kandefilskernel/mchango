# Plan — Achats groupés et groupes multi-activités

> Brouillon du 14 novembre 2026, issu des PDF « Concept visuel » et « Philosophie fondatrice ». Rien n'est encore implémenté. Les points marqués **[À TRANCHER]** bloquent la conception.

## 1. Ce qui change

| Avant (v0.2) | Après |
|---|---|
| Produit = tontine numérique | Promesse unique = « Avec ton groupe, achète moins cher » |
| Le groupe = un likelemba | Le groupe est permanent et porte plusieurs activités (achats proposés, likelemba) |
| Aucun commerce | Commerçants, offres à paliers, réservations, retrait en boutique |
| Inscription obligatoire | Offres consultables sans compte ; identification à la confirmation |
| Back-office reporté | Nécessaire tôt pour les commerçants et les offres (ou une app commerçant) |

**Ce qui se réutilise tel quel :** double regard, journal chaîné, rôles, OTP/PIN, appareils, notifications, montants en entiers, toutes les garanties de la base.

**Ce qui entre en tension avec la doc actuelle :**
- Principe P1 (« aucun solde, aucune cagnotte ») : reste vrai **si le commerçant encaisse lui-même**. Il faut le réécrire pour dire explicitement que Mchango ne touche jamais l'argent des achats. Si Mchango devait encaisser pour le commerçant, la règle de garde (§1 de l'architecture) s'applique : validation juridique avant toute conception.
- `docs/architecture.md` décrit le pilote comme 10–20 groupes de tontine à Lubumbashi. À reformuler en pilote d'achats groupés avec 1 à 3 boutiques.

## 2. Modèle de données (migration `db/003_achats.sql`)

Nouvelles tables, sans toucher aux tables existantes sauf mention :

| Table | Rôle |
|---|---|
| `merchants`, `merchant_members` | Boutique partenaire (nom, zone de retrait) et ses employés autorisés à vérifier les codes |
| `pickup_zones` | Zones de retrait (commune/quartier), pour filtrer les offres |
| `offers` | Produit, boutique, prix habituel, quantité cible, date de fin, devise, statut |
| `offer_tiers` | Paliers : à partir de N unités, prix P |
| `orders` | Une réservation = (offre, acheteur, quantité, nom de retrait). Une seule commande active par acheteur et offre |
| `order_payments` | Déclaration de paiement (acheteur) puis confirmation (commerçant) : même double regard que les cotisations |
| `pickups` | Code de retrait (`MC-xxxx`), remise confirmée par le commerçant |
| `shares` | Chaque partage d'une offre : qui, vers quel groupe ou WhatsApp, et `parent_share_id` pour l'origine des invitations |
| `group_offer_proposals` | « Achats proposés » dans un groupe permanent : offre, proposeur |
| `guests` | Identité légère avant l'OTP, pour rattacher un clic WhatsApp à une session |

**Changements dans l'existant :**
- `groups` : ajouter les activités activées (achats toujours possibles, likelemba facultatif). Les tables `cycles`, `contributions`, `confirmations` restent le module likelemba.
- Journal : l'enchaînement par groupe ne convient pas aux commandes, qui existent sans groupe. Ajouter des chaînes `offer:<uuid>` (offre, ses commandes, paiements et retraits). Le trigger `audit_business_change()` et la vérification Dart doivent accepter ce préfixe : à vérifier dans `chain_verifier.dart`.

**Règles à faire porter par la base (comme pour la tontine) :**
- Le compteur « unités confirmées » est **calculé** depuis `orders` confirmées, jamais saisi ni incrémenté par une invitation.
- Une commande n'est comptée qu'une fois, quel que soit le nombre de groupes où l'offre a circulé (unicité offre + acheteur).
- Seul le commerçant de l'offre peut confirmer un paiement ou un retrait.
- Un paiement déclaré n'est pas un paiement vérifié : deux statuts distincts.
- Pas de suppression physique ; rôle `mchango_app` sans `DELETE`.

**Cycles de vie :**
- Offre : `draft → open → closed (seuil atteint) → fulfilled`, ou `→ cancelled` si seuil non atteint à la date de fin.
- Commande : `reserved → payment_declared → paid → ready → picked_up`, avec `cancelled`, `expired`, `no_show`.

## 3. API (NestJS, modules à ajouter)

- `merchants` : onboarding (via back-office), employés.
- `offers` : liste publique par zone (sans authentification, avec cache), détail, paliers, création/clôture par le commerçant.
- `orders` : réserver, annuler avant clôture, déclarer le paiement, mes commandes.
- `pickups` : vérifier un code, confirmer la remise (commerçant).
- `shares` : créer un partage, résoudre un lien d'invitation, enregistrer l'origine.
- `groups` : proposer une offre à un groupe, liste « Achats proposés ».
- Jobs BullMQ : clôture à la date de fin, ouverture de la fenêtre de paiement, expiration des réservations non payées, rappels de retrait.
- Contrainte : l'API se connecte avec `mchango_app` et ouvre chaque transaction avec `SET LOCAL mchango.actor_*` (règle de `db/README.md`).

## 4. Mobile (Flutter)

1. **Accueil/marketplace** sans compte : choix de zone, recherche, cartes d'offres avec compteur.
2. **Fiche offre** : prix habituel/collectif, paliers, compteur, deux boutons Participer / Inviter.
3. **Participer** : quantité, nom de retrait, OTP seulement à la confirmation.
4. **Inviter** : partage vers un groupe Mchango ou WhatsApp. Liens profonds (Android App Links) pour ouvrir directement l'offre.
5. **Mes commandes** : statuts, code de retrait.
6. **Groupe** : hub avec Achats proposés, Likelemba (module existant), Membres.
7. **Espace commerçant** (si dans l'app) : commandes à retirer, saisie du code, confirmation. **[À TRANCHER]** sinon web.

Prérequis : mettre à jour Flutter (en cours), puis valider que le test du paquet et de l'app mobile passent avant de commencer.

## 5. Back-office (Next.js)

Avancé du « plus tard » vers l'itération 1 : création de commerçants, saisie des offres et paliers, suivi des commandes et retraits, vérification de chaîne. Si le commerçant n'a pas d'app, c'est aussi son outil.

## 6. Ordre de réalisation

| Étape | Contenu | Critère de fin |
|---|---|---|
| **0. Décisions** | Questions ouvertes (§8) ; mise à jour de `docs/architecture.md` (P1, pilote, périmètre) | Décisions écrites |
| **1. Base et spec** | `003_achats.sql`, tests `db/tests/002_achats.sql` (doubles comptages, paliers, confirmation par le seul commerçant), chaînes `offer:`, mise à jour des vecteurs et du vérificateur Dart | Tests DB et `dart test` verts |
| **2. API** | Modules offers, orders, pickups, shares ; endpoints publics ; jobs de clôture | Tests unitaires et e2e du parcours réservation → retrait |
| **3. Tranche mince mobile** | Une offre → participer → code de retrait, avec un commerçant de test | Un acheteur de test va jusqu'au retrait sans aide |
| **4. Social** | Inviter, liens profonds, Achats proposés, origine des invitations | Même commande jamais comptée deux fois |
| **5. Commerçant et pilote** | Espace commerçant ou back-office, 1 à 3 boutiques réelles | Une offre réelle clôturée et retirée |
| **6. Likelemba dans le hub** | Raccorder le module existant, sans le promouvoir | Tests existants toujours verts |

Chaque étape finit par : base, `dart test`, `npm test` de l'API, build du back-office, `flutter test`.

### État au 14 novembre 2026 : base et API faites, sur la branche `backoffice`

Les étapes 1 et 2 ont d'abord été écrites à partir de `main`, puis refaites par-dessus `backoffice` (qui avait déjà la connexion, 18 migrations et l'app mobile). Ce qui est livré :

- `db/019_achats.sql` et `db/tests/005_achats.sql` (51 vérifications, après les tests 001 à 004).
- `apps/api/src/purchases/` : offres, commandes, partages, encaissement et retrait, clôture périodique. 7 tests e2e (`test/purchases.e2e-spec.ts`), avec de vraies inscriptions par SMS.
- Routes et règles : [`spec/achats.md`](../spec/achats.md).

Adaptations à `backoffice` :
- **Journal** : la chaîne `offer:<uuid>` s'ajoute à la répartition par auteur de `017` ; boutiques et zones vont dans la chaîne de leur auteur. Fonction de journalisation à part (`audit_purchase_change`), celle de la tontine n'est pas modifiée.
- **Connexion** : celle de `backoffice` (`AccessGuard`, jetons de 15 minutes, défi signé par l'appareil). La connexion écrite sur `main` est abandonnée.
- **Groupes sans tontine** : retirés de cette migration. Une offre se propose à un groupe de tontine ; un groupe d'achat seul est une étape à part (écrans, règlement signé).
- **Clôture** : sur le modèle des rappels (`PURCHASES_JOBS_ENABLED`, `PURCHASES_JOBS_INTERVAL_SECONDS`).
- **Vecteurs du journal** (`spec/test-vectors/audit_chain.json`) : non régénérés. Le vérificateur Dart traite `chain_id` comme une chaîne opaque ; les régénérer changerait tous les hash existants pour un gain faible.

Écarts par rapport au §2, toujours valables :
- **Pas de table `guests`.** Une commande exige un utilisateur vérifié par OTP ; avant cela le visiteur ne laisse aucune trace en base. Un partage peut avoir un auteur inconnu (`shared_by_user_id` NULL).
- **Pas de table `group_offer_proposals`.** Un partage vers un groupe *est* la proposition ; `group_offer_proposals` est une vue calculée.
- **`order_payments`** accepte deux chemins : l'acheteur déclare puis la boutique confirme, ou la boutique saisit directement au comptoir.
- **Le vérificateur Dart n'a pas changé** : il traitait déjà `chain_id` comme une chaîne opaque.
- **Pas de suppression de palier** (aucun `DELETE` nulle part) : pour retirer un palier d'un brouillon, annuler le brouillon et en recréer un.

- **Un partage exige un compte.** Un visiteur sans compte retransmet le lien qu'il a reçu.

Étape 3 (mobile), dans l'app existante : offres par zone, fiche, réservation, invitation (groupe ou WhatsApp), mes commandes avec code de retrait, achats proposés d'un groupe, espace boutique (comptoir, création d'offre). 8 tests d'écran ; textes en quatre langues (swahili et lingala à faire relire).

Non fait :
- Consulter les offres sans compte dans l'app, et lien WhatsApp qui ouvre l'offre (domaine web et liens d'app Android).
- Essai sur un vrai téléphone, et parcours complet de l'app contre la vraie API.
- Création des boutiques, employés et zones depuis le back-office (aujourd'hui : en base).
- `docs/architecture.md` ne parle pas encore des achats groupés.
- Pas de limite de stock (`max_quantity`) sur une offre.
- L'expiration d'une commande après le délai de retrait est refusée avant l'échéance (testé) ; le cas accepté n'est pas testé, faute de pouvoir avancer l'horloge.

## 7. Risques propres à ce changement

- **Faux compteur** : tout raccourci qui compte invitations ou intentions détruit la confiance. La règle est portée par la base.
- **Non-paiement à la clôture** : un acheteur réserve et ne paie pas, le seuil tombe. Définir délais et sanctions **[À TRANCHER]**.
- **Commerçant qui ne tient pas le prix** : Mchango n'a pas de levier contractuel au départ. Accord écrit par offre.
- **Juridique** : commission sur la vente, statut d'intermédiaire commercial, protection du consommateur : à faire vérifier, comme le reste du §8 de l'architecture.
- **Fuite de données du likelemba** : les groupes mélangent maintenant achats et finances ; les données financières restent privées par défaut.

## 8. Décisions (14 novembre 2026)

| Sujet | Décision | Conséquence |
|---|---|---|
| Encaissement | **Le commerçant encaisse en boutique** | P1 reste vrai : Mchango ne touche jamais l'argent des achats. Le statut « payé » est confirmé par le commerçant (double regard). |
| Prix et seuil | **Palier atteint à la clôture ; offre annulée si le seuil minimum n'est pas atteint** | Rien n'est payé avant la clôture, donc aucun remboursement à gérer. Le prix affiché pendant l'offre est indicatif. |
| Création des offres, retraits | **Espace commerçant dans l'app mobile** | Le commerçant crée ses offres et vérifie les codes depuis l'app. Un rôle commerçant dans le mobile, des écrans dédiés, et une création d'offre côté API. Le back-office se limite à créer et activer les boutiques. |
| Ville pilote | **Les deux, une boutique chacune** (Lubumbashi et Kinshasa-Matete) | Zones et devise à prévoir pour deux villes ; double suivi du pilote. |
| Délais | **Fixés par chaque commerçant, par offre** | Champ `pickup_window_hours` sur l'offre, borné par l'équipe. Hypothèse retenue : pas de pénalité financière ; un no-show est enregistré dans la mémoire du groupe et du commerçant. **À confirmer.** |
| Zones | **Liste fermée par commune**, gérée par l'équipe | Table `pickup_zones` alimentée à la main avant le pilote. |

Impact sur le plan :
- §5 : le back-office perd la saisie des offres. Il garde la création des boutiques, des zones et le suivi.
- §4 : l'espace commerçant du mobile passe de « si dans l'app » à **obligatoire** à l'étape 5, et sa tranche mince (créer une offre, vérifier un code) rejoint l'étape 3.
- §3 : l'API doit authentifier un commerçant (rôle) et vérifier qu'il agit seulement sur ses offres.

Reste à confirmer :
1. Absence de pénalité financière pour un no-show.
2. Bornes min/max de la fenêtre de retrait imposées aux commerçants.
3. Qui crée le compte du commerçant (l'équipe via le back-office, probable).
