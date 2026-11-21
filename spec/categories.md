# Catégories de tontine

> Version 0.2 — 8 novembre 2026 — **étape 1 (socle) implémentée** : voir la section 7. Le reste est de la spécification.

Une tontine appartient à une **catégorie** choisie à sa création. La catégorie ne change pas la nature de Mchango (voir « Invariants ») : elle fixe les **rôles**, les **règles par défaut** et les **fonctions** disponibles, du plus simple (entre voisins) au plus évolué (une communauté religieuse).

## 1. Les quatre catégories

Du niveau le plus simple au plus évolué. L'ordre reprend celui de la demande ; il se change sans toucher au reste.

| # | Catégorie | Code | Pour qui | Niveau |
|---|-----------|------|----------|--------|
| 1 | **Communautaire** | `community` | Voisins, amis, marchands, taxi-motos, associations de quartier. | Base : c'est la tontine actuelle. |
| 2 | **Organisation** | `organization` | Associations, coopératives, syndicats, ONG, mutuelles. | Bureau, plusieurs groupes sous une même organisation, rapports. |
| 3 | **Travailleurs** | `workers` | Collègues d'un même employeur ou d'un même métier, fonctionnaires. | Calendrier calé sur la paie, confidentialité renforcée. |
| 4 | **Religion** | `religion` | Églises, paroisses, mosquées, communautés et leurs groupes (femmes, jeunes, chorales). | Le plus évolué : comité de gestion, plusieurs caisses, promesses, rapports aux responsables. |

Le champ existant `groups.type` (`formel` / `informel`) reste tel quel : c'est une autre question (le groupe est-il structuré ou non ?). Une organisation est le plus souvent `formel`, mais ce n'est pas imposé.

## 2. Invariants : ce qui ne change dans aucune catégorie

- **Non-détention des fonds.** Aucune catégorie n'ouvre de compte, de portefeuille ni de solde.
- **Double regard.** Une cotisation n'est confirmée que par le payeur **et** le receveur (et le témoin en espèces).
- **Journal en ajout seul.** Toutes les décisions et tous les rôles sont journalisés.
- **L'équipe Mchango ne confirme jamais un paiement.**
- **Pas de garantie.** Les textes (règlement, reçus) disent que Mchango ne garantit, ne rembourse et ne recouvre rien.

> ⚠️ **Règle de garde.** Une fonction qui ferait **transiter, conserver ou garantir** de l'argent (cagnotte tenue par Mchango, prélèvement sur salaire, paiement dans l'app) est refusée dans toutes les catégories tant qu'un juriste congolais ne l'a pas validée. Les points concernés sont marqués 🔒 ci-dessous.

## 3. Ce que chaque catégorie apporte

Légende : ✅ prévu dans la première version de la catégorie · ⏭ plus tard · 🔒 touche à l'argent ou à la loi : validation juridique d'abord · — non applicable.

### 3.1 Rôles

| Rôle | Communautaire | Organisation | Travailleurs | Religion |
|------|:---:|:---:|:---:|:---:|
| Membre | ✅ | ✅ | ✅ | ✅ |
| Président (organisateur) | ✅ | ✅ | ✅ | ✅ |
| Trésorier (mode collecteur) | ✅ (existe déjà) | ✅ | ✅ | ✅ |
| Secrétaire | — | ✅ | — | ✅ |
| Commissaire aux comptes (lecture seule, contrôle) | — | ✅ | — | ✅ |
| Responsable religieux (lecture des rapports, sans pouvoir de confirmer) | — | — | — | ✅ |

Le commissaire aux comptes et le responsable religieux **lisent** et **signalent** ; ils ne confirment jamais une cotisation à la place du receveur.

### 3.2 Règles par défaut

| Règle | Communautaire | Organisation | Travailleurs | Religion |
|-------|---------------|--------------|--------------|----------|
| Taille maximale | 2 à 100 (30 par défaut) | jusqu'à 500, par sous-groupe | 2 à 100 | jusqu'à 500, par sous-groupe |
| Fréquence | jour, semaine, mois | semaine, mois | **mois, à une date de paie** | semaine, mois |
| Mode de versement | direct (défaut) | direct ou trésorier | direct (défaut) | direct ou trésorier |
| Changement de règle en cours de cycle | décision du président avec accord de la majorité | **vote du bureau** | majorité des membres | **vote du comité de gestion** |
| Visibilité des cotisations de chacun | tout le groupe | tout le groupe | **bénéficiaire, payeur et organisateur seulement** | selon la caisse (voir 3.4) |

### 3.3 Fonctions

| Fonction | Communautaire | Organisation | Travailleurs | Religion |
|----------|:---:|:---:|:---:|:---:|
| Parcours actuel (déclaration, confirmation, reçus, journal, rappels) | ✅ | ✅ | ✅ | ✅ |
| Règlement signé, tirage vérifiable | ✅ | ✅ | ✅ | ✅ |
| **Organisation parente** : plusieurs tontines regroupées sous une même entité, avec une vue d'ensemble | — | ✅ | ⏭ (un employeur) | ✅ (la communauté) |
| **Bureau / comité** : décisions à plusieurs voix, journalisées | — | ✅ | — | ✅ |
| **Rapports PDF** (état des cotisations, retards, litiges) | ⏭ | ✅ | ⏭ | ✅ |
| **Rapports pour les responsables** (agrégés) | — | ✅ | — | ✅ |
| **Calendrier calé sur la paie** (échéance à la date de paie, rappel après) | — | — | ✅ | — |
| **Vue employeur anonymisée** (nombre de groupes et taux de paiement, sans noms) | — | — | ⏭ | — |
| **Plusieurs caisses** dans une communauté (entraide, projets, etc.) | — | ⏭ | — | ✅ |
| **Promesses** : engagement d'un membre, suivi du réalisé par rapport au promis | — | ⏭ | — | ✅ |
| **Dons et dîme** | — | — | — | 🔒 |
| **Prélèvement sur salaire par l'employeur** | — | — | 🔒 | — |
| Import de la liste des membres (fichier) | — | ✅ | — | ✅ |
| Score de confiance, pénalités | ⏭ V2 | ⏭ V2 | ⏭ V2 | ⏭ V2 |

### 3.4 Détail de la catégorie « Religion » (la plus évoluée)

C'est la catégorie où il y a le plus à décider, et le plus de risque.

1. **Une communauté, des tontines.** La communauté (organisation parente) regroupe des tontines : groupe des femmes, des jeunes, de la chorale, cellules de quartier. Chaque tontine reste une tontine ordinaire avec rotation des tours.
2. **Comité de gestion.** Les décisions qui engagent le groupe (changer une règle, désigner un trésorier, suspendre un membre) sont prises par vote du comité et inscrites dans le journal avec le détail des voix.
3. **Plusieurs caisses.** La communauté peut tenir des caisses distinctes (par exemple entraide et projets). Une caisse est une **liste de contributions déclarées et confirmées**, comme une cotisation : Mchango n'en tient pas le solde.
4. **Promesses.** Un membre s'engage sur un montant ; l'application suit le promis, le déclaré et le confirmé. Une promesse n'est **pas** une dette exigible : le texte le dit.
5. **Confidentialité.** Pour les caisses de type don, le détail par personne n'est visible que du membre concerné, du trésorier et du commissaire aux comptes ; les autres voient des totaux.
6. **Rapports.** Rapport périodique pour les responsables : totaux par caisse, taux de confirmation, litiges ; sans noms par défaut.

🔒 **Dons et dîme.** Ce ne sont pas des tontines : il n'y a pas de rotation, et l'argent va à une caisse tenue par un trésorier. Même si Mchango n'en détient rien, cela rapproche le produit d'une **collecte de fonds**, avec des risques précis : réglementation des collectes, lieu de la confiance (Mchango pris pour un garant), conflits internes à la communauté. **Cette partie n'est pas conçue** avant avis juridique. La première version de « Religion » se limite aux points 1, 2, 5 et 6, appliqués à des tontines à rotation.

### 3.5 Détail de la catégorie « Travailleurs »

- **Calendrier de paie.** Le président fixe un jour de paie (par exemple le 25) ; l'échéance et le rappel s'alignent dessus. Si le jour tombe un dimanche ou un jour férié, la règle de report est fixée à la création.
- **Confidentialité.** Les collègues d'un même service ne doivent pas voir qui est en retard : seuls le payeur, le bénéficiaire et l'organisateur voient l'état d'une cotisation.
- 🔒 **Retenue sur salaire.** Une retenue faite par l'employeur et versée au bénéficiaire fait transiter de l'argent par un tiers : hors périmètre tant qu'un juriste ne l'a pas validée. Mchango resterait seulement un **registre** de ce qui a été déclaré.

## 4. Ce que cela change dans le produit

### 4.1 Base de données (migration `018`)

- Nouveau type `group_category` : `community`, `organization`, `workers`, `religion`.
- `groups.category group_category NOT NULL DEFAULT 'community'` : tous les groupes existants deviennent `community`. `groups.type` ne change pas.
- La catégorie **ne se modifie jamais après la création**, comme la devise (un trigger de la base le refuse). Elle n'entre donc pas dans l'empreinte du règlement (`terms_hash`) : elle ne peut pas changer, il n'y a rien à re-signer.
- Nouveaux rôles de membre : `secretary`, `auditor` (puis `clergy` ou équivalent pour Religion) dans `member_role`.
- Plus tard : table `organizations` (organisation parente) et `groups.organization_id`, table `funds` pour les caisses, table `pledges` pour les promesses, `group_decisions` pour les votes du comité. Chacune en **ajout seul**, avec triggers de journal, comme le reste.
- Aucune table de solde, dans aucune catégorie.

### 4.2 API

- `POST /groups` accepte `category` (défaut `community`). Un champ inconnu est refusé.
- `GET /group-categories` renvoie, pour chaque catégorie, ses règles par défaut et ses fonctions actives : l'application affiche ce qui est permis **sans coder la liste en dur**.
- Les contrôles de rôle et de limite (taille, fréquence autorisée) sont faits **par l'API** ; l'application ne fait que masquer.
- Les profils de catégorie vivent dans un fichier de configuration du code (`apps/api/src/groups/categories.ts`), pas dans la base, pour qu'un changement soit relu et versionné.

### 4.3 Application mobile

- À la création : choix de la catégorie sur quatre cartes avec une phrase d'explication, avant le nom et le montant.
- L'écran du groupe affiche la catégorie et n'offre que les fonctions de sa catégorie.
- Textes du règlement adaptés par catégorie (par exemple « promesse, pas dette » pour Religion).

### 4.4 Back-office

- Filtre et colonne « catégorie » sur la liste des tontines ; tableau de bord ventilé par catégorie.
- Seuils d'alerte par catégorie (`ALERT_RULES`) : un comité de 300 personnes n'a pas les mêmes ordres de grandeur que dix voisins.
- Rapports et exports par catégorie.

### 4.5 Journal

- La catégorie du groupe est inscrite dans l'événement de création (`group.created`).
- Les décisions du bureau ou du comité sont des événements du journal, avec les voix.

## 5. Lien avec le modèle économique

Le cadrage prévoit que les groupes informels paieront peu et que la valeur viendra du **B2B** (églises, associations, syndicats, coopératives). Les catégories rendent cela concret :

- **Communautaire** : gratuit ou très bas prix, c'est la porte d'entrée.
- **Organisation, Travailleurs, Religion** : fonctions à valeur (rapports, bureau, vue d'ensemble) pouvant être facturées à la structure.

La facturation est prévue en **V2** ; rien n'est branché ici. La grille de prix reste à tester au pilote.

## 6. Risques

| Risque | Parade |
|--------|--------|
| « Religion » glisse vers la collecte de dons et change la nature juridique | Dons et dîme exclus de la première version ; avis juridique avant toute conception (3.4). |
| Trop de fonctions pour une équipe réduite | Livrer par étapes (section 7) ; Communautaire reste le seul parcours obligatoire. |
| Un responsable d'organisation utilise le journal pour surveiller des individus | Confidentialité par défaut pour Travailleurs et les caisses de don ; rapports agrégés. |
| Confusion entre catégorie et niveau de confiance | La catégorie ne mesure aucune fiabilité ; le score de confiance est un autre chantier (V2). |
| Employeur qui impose la tontine à ses salariés | Adhésion volontaire, jamais décidée par l'employeur ; la vue employeur est anonymisée. |
| Les catégories deviennent des cases où l'on enferme des groupes mixtes | Catégorie unique par groupe, mais une organisation parente peut regrouper des groupes de catégories différentes (à décider). |

## 7. Ordre de réalisation proposé

1. **Socle — fait** : migration `018`, `category` dans l'API et à la création de groupe, `GET /group-categories`, choix de la catégorie dans l'app, colonne et filtre dans le back-office. Tous les groupes restent `community` par défaut ; les quatre catégories se comportent encore de la même façon (`features` vide). Tests : `db/tests/004_category.sql`, `apps/api/test/groups.e2e-spec.ts` (section « catégories »), `apps/mobile/test/category_test.dart`.
2. **Travailleurs — fait** : `db/023_payday.sql`. Jour de paie (1 à 31, 31 = dernier jour du mois) et règle de report (`before` : jour ouvré précédent, `after` : suivant) si l'échéance tombe un dimanche ou un jour férié (table `public_holidays`, **liste à faire valider**). Seulement pour une tontine mensuelle « Travailleurs » (contrainte de la base). Le jour de paie entre dans l'empreinte du règlement signé ; le rappel SMS part le jour de paie, pas la veille. Confidentialité : dans le détail d'un tour, un collègue ne voit que sa propre ligne (statut `private` pour les autres) ; le payeur, le bénéficiaire, le président et le témoin d'une remise en espèces voient la leur. `features` de « Travailleurs » : `payday_calendar`, `private_statuses`. Tests : `apps/api/test/features.e2e-spec.ts`.
   **Journal confidentiel** (`db/024_private_slot_chains.sql`) : dans une tontine « Travailleurs », les déclarations, confirmations et contestations ne vont plus dans la chaîne du groupe mais dans une **chaîne privée par case de paiement** (`group:<groupe>:slot:<tour>:<payeur>`). `GET /groups/:id/private-history` ne renvoie à chacun que les chaînes qu'il a le droit de voir (payeur, bénéficiaire du tour, témoin, président), en entier, pour qu'il les vérifie sur son téléphone comme la chaîne du groupe. La chaîne du groupe garde le reste (membres, tours, clôture d'un tour) : elle reste vérifiable par tous. Les événements écrits avant la migration 024 restent où ils sont (ajout seul).
   Limite restante : une chaîne privée n'est ancrée nulle part dans la chaîne du groupe ; un membre détecte une réécriture de ce qu'il a déjà vérifié, mais pas une chaîne privée qu'on ne lui aurait jamais montrée. Un ancrage périodique (empreinte de toutes les têtes de chaînes) est prévu avec l'ancrage public V2.
3. **Organisation** : rôles secrétaire et commissaire aux comptes, vote du bureau, rapports PDF, import des membres.
4. **Religion, première version** : organisation parente, comité de gestion, rapports agrégés, confidentialité.
5. **Après avis juridique** : caisses, promesses, dons, retenue sur salaire.

## 8. Questions ouvertes

1. L'**ordre** des catégories : est-ce bien Communautaire, Organisation, Travailleurs, Religion du plus simple au plus évolué ?
2. Une **religion** précise est-elle visée en premier (églises, mosquées), ou toutes ? Les usages (dîme, offrandes, entraide) diffèrent.
3. « Organisation » et « Religion » se ressemblent beaucoup : doivent-elles rester deux catégories, ou une seule avec une option « communauté de foi » ?
4. Le **plafond de taille** (500) convient-il ? Une grande paroisse dépasse ce chiffre.
5. ~~Une catégorie peut-elle changer avant le démarrage ?~~ Tranché à l'étape 1 : non, elle est fixée à la création. À rouvrir si les présidents se trompent souvent de catégorie.
6. Qui peut créer une organisation parente : n'importe qui, ou après vérification par l'équipe Mchango ?
7. Avis juridique à obtenir : collecte de fonds et dons, retenue sur salaire, protection des données de pratique religieuse (donnée sensible).
