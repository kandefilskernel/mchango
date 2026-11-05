# Back-office : administration par l'équipe

Implémentation :
- API : [`apps/api/src/admin/`](../apps/api/src/admin/) ;
- interface web : [`apps/backoffice/`](../apps/backoffice/) (Next.js).

Tests : [`apps/api/test/admin.e2e-spec.ts`](../apps/api/test/admin.e2e-spec.ts), [`apps/api/src/admin/totp.spec.ts`](../apps/api/src/admin/totp.spec.ts) (vecteurs de la RFC 6238).

Périmètre : les modules **MVP** de la section 8.3 du document de cadrage.

| Module | Contenu |
|--------|---------|
| Tableau de bord | Inscrits, nouveaux, bloqués ; tontines par statut ; paiements déclarés et confirmés du jour ; taux de retard sur 30 jours ; litiges ouverts ; « PIN oublié » en attente ; SMS en échec. **Pas de revenus** : la facturation est prévue en V2. |
| Utilisateurs | Recherche par nom ou numéro ; fiche (tontines, téléphones liés, historique du compte) ; blocage avec motif, déblocage ; révocation d'un téléphone. |
| Tontines | Recherche, filtre par statut ; fiche (tours, membres, ordre des tours, journal, vérification de la chaîne) ; suspension avec motif, réactivation. |
| Litiges | File (ouverts, clos) ; rejet d'une déclaration ou avis consultatif. |
| Audit | Journal par chaîne (`global` ou une tontine) ; vérification d'intégrité ; actions de l'équipe. |
| Équipe | Comptes, rôles, désactivation (super admin). Création avec mot de passe provisoire et QR code 2FA affichés une seule fois. |

## Sécurité

- **Connexion** : e-mail + mot de passe (argon2id, 12 caractères minimum) + **code TOTP à 6 chiffres**, toujours. 5 échecs bloquent le compte 15 minutes. Le message d'erreur est le même quel que soit le facteur faux.
- **Secrets 2FA** chiffrés en base (AES-256-GCM, clé `STAFF_SECRET_KEY`) ; jetons de l'équipe signés avec `STAFF_JWT_SECRET`, distinct de celui des membres. Un jeton de membre n'ouvre pas le back-office.
- **Session** : 8 h, dans un cookie `httpOnly` + `SameSite=Strict`, inaccessible au JavaScript du navigateur. Le serveur Next.js appelle l'API ; le navigateur ne voit jamais le jeton.
- **Compte désactivé** : session coupée immédiatement (le compte est revérifié à chaque requête).
- **Premier mot de passe** provisoire : changement demandé à la première connexion.
- **Il reste toujours un super admin actif**, et personne ne modifie son propre compte depuis la page Équipe.

## Rôles

| Rôle | Lire | Voir les numéros | Bloquer, révoquer un téléphone, débloquer un PIN, notes, renvoi SMS | Valider un « PIN oublié » | Suspendre une tontine | Trancher un litige | Exports CSV | Gérer l'équipe |
|------|:----:|:----------------:|:------------------------------:|:--:|:---------------------:|:------------------:|:--:|:--------------:|
| Super admin | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Conformité | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Support | ✓ | ✓ | ✓ | | | | | |
| Finance | ✓ | masqués (`+243 99 *** **67`) | | | | | ✓ | |
| Lecture seule | ✓ | masqués | | | | | | |

Les droits sont contrôlés **par l'API**. L'interface ne fait que masquer les boutons inutiles.

## Ce que l'équipe peut faire, et ce qu'elle ne peut pas faire

- Toute action est inscrite dans le **journal**, avec l'acteur « staff ». Celles qui concernent une tontine (suspension, décision de litige) vont dans **la chaîne de cette tontine** et sont donc **visibles des membres** dans leur historique.
- **Litige, rejet** : la déclaration passe `rejected` et le litige `resolved_rejected` ; le payeur peut déclarer de nouveau, avec un vrai ID de transaction.
- **Litige, avis** : la note est ajoutée, le litige reste ouvert ; les parties s'accordent.
- L'équipe **ne peut jamais confirmer un paiement** à la place du bénéficiaire : elle ne voit pas l'argent. Elle ne peut pas rejeter un paiement déjà confirmé par le bénéficiaire.
- **Suspension** : plus de déclarations ni de rappels ; la réactivation rend le statut d'avant (préparation ou en cours).

## Page « À traiter » (`GET /admin/inbox`)

Les membres qui ont besoin de l'équipe, en une page. Le menu affiche le nombre total de cas, et le tableau de bord les reprend en tête.

| Cas | Action possible |
|-----|-----------------|
| « PIN oublié » en attente (signalé après 24 h sans réponse d'un garant) | **Valider le nouveau PIN** (`POST /admin/pin-resets/:id/approve`, conformité et super admin) avec une **note de vérification d'identité obligatoire** (15 caractères au moins). La note est conservée (`pin_reset_requests.staff_note`) et la validation entre dans le journal de **chaque tontine** du membre (`staff.pin_reset_approved`) : les membres la voient. |
| PIN bloqué (5 erreurs, 30 min) | **Débloquer le PIN** (`POST /admin/users/:id/unlock-pin`), après avoir parlé à la personne. Journal : `staff.pin_unlocked`. |
| Litiges ouverts | Lien vers la file des litiges. |
| SMS en échec (7 jours) | Lecture : la personne n'a pas reçu son code ou son rappel. |
| Tontines suspendues | Lien vers la tontine pour la réactiver. |

| Suivis en cours | Notes « à suivre » non closes (voir plus bas). |

## Fiche membre : SMS, notes de suivi

- **SMS reçus** : les 30 derniers, avec l'état (envoyé, échec et sa cause). Les codes de connexion ne sont jamais conservés, donc jamais affichés ni renvoyés.
- **Renvoyer un rappel en échec** (`POST /admin/notifications/:id/resend`, support, conformité, super admin) : seulement un rappel de cotisation, seulement si le paiement n'est pas encore déclaré et le tour pas clos, **une fois** par SMS en échec, **3 renvois au plus** par membre et par jour (`429` au-delà). Journal : `staff.sms_resent`.
- **Notes de suivi** (`POST /admin/users/:id/notes`, mêmes rôles) : internes, jamais visibles du membre, ni modifiables ni supprimables (`support_notes`, migration 012). « À suivre » fait apparaître la note dans « À traiter » ; une note de clôture (`closes`) l'en retire, une seule fois. Le journal garde l'ajout (`staff.support_note`, `staff.follow_up_closed`) mais pas le texte.
- **Débloquer le PIN** est aussi possible depuis la fiche.

## Alertes (`GET /admin/alerts`)

Signaux à vérifier, **pas des preuves** : rien n'est bloqué ni gelé automatiquement.

| Signal | Seuil |
|--------|-------|
| ID de transaction déclaré plusieurs fois (une déclaration rejetée puis reprise, par exemple) | 2 déclarations |
| « PIN oublié » répétés (vol de carte SIM ?) | 2 demandes en 30 jours |
| Nouveaux téléphones liés | 3 en 7 jours |
| Déclarations rejetées | 2 en 30 jours |

Les seuils sont dans `ALERT_RULES` (`apps/api/src/admin/admin.service.ts`) : à ajuster avec les vrais usages.

## Avis des membres et agent IA (`/feedback`, `/admin/ai/…`)

**Avis.** Dans l'app, menu « Donner mon avis » : un texte (3 à 2 000 caractères), une note de 1 à 5 facultative, à propos de Mchango ou d'une de ses tontines actives (`POST /feedback`). 5 avis par jour et par membre au plus. Les avis ne se modifient ni ne s'effacent.

**Analyse d'une tontine** (`POST /admin/ai/groups/:id/review`, fiche de la tontine). Deux étages :
1. **Règles automatiques, sans IA**, toujours calculées (`apps/api/src/ai/signals.ts`) :

| Règle | Seuil |
|-------|-------|
| ID de transaction déjà utilisé dans une autre déclaration | 1 |
| Déclaration pas confirmée par le bénéficiaire | après 72 h |
| Retards du même payeur | 2 |
| Contestations contre le même payeur | 2 |
| Déclaration rejetée | 1 |
| Même témoin pour le même payeur en espèces | 2 fois |

2. **Agent IA** (Claude, `claude-opus-5-5`, si `ANTHROPIC_API_KEY` est configurée) : il relit les cotisations, les délais de confirmation, les litiges et les avis, confirme ou nuance les règles, et rend des constats structurés (gravité, catégorie, membres, preuves, action proposée) et un niveau de risque. En cas de surcharge, l'API d'Anthropic bascule d'elle-même sur un modèle de secours (option `fallbacks: "default"`) ; le modèle réellement utilisé est noté.

**Synthèse des avis** (`POST /admin/ai/feedback/review`, page « Analyse IA ») : thèmes récurrents des 30 derniers jours, sentiment, et avis urgents (arnaque signalée, argent non reçu, compte piraté).

Règles de conduite :
- **Avis, jamais décision.** L'agent ne bloque, ne suspend, ne rejette rien, et ne touche à aucun argent. Toute mesure reste une décision humaine, après vérification (appel, capture du SMS opérateur).
- **Pseudonymisation.** L'agent reçoit M1, M2… (membres) et F1, F2… (avis), jamais les noms, numéros de téléphone ou identifiants internes ; noms et numéros sont aussi retirés des textes libres (avis, motifs de litige). La correspondance reste en base et sert seulement à réafficher les vrais noms dans le back-office. Le retrait des noms dans les textes ne couvre que les noms enregistrés : un surnom ou un nom mal orthographé peut passer.
- **Droits.** Lire : toute l'équipe. Lancer une analyse (facturée) : super admin, support, conformité. Plafond `AI_REVIEWS_PER_DAY` (30 par défaut) ; au-delà, les règles seules tournent.
- **Traçabilité.** Chaque analyse est gardée (`ai_reviews` : règles, réponse, modèle, jetons, erreur) et journalisée (`staff.ai_review`).
- **À vérifier avant la production** : base légale de l'envoi de données (même pseudonymisées) à un prestataire hors de RDC, mention dans la politique de confidentialité, et conditions d'utilisation et de conservation des données côté Anthropic.

Sans clé, ou si l'agent est indisponible, l'analyse est quand même enregistrée avec les règles seules et la raison.

## Exports CSV (`GET /admin/export?kind=…`)

`disputes` (tous les litiges), `late` (paiements attendus et non déclarés, 30 derniers jours), `audit` (une chaîne entière avec ses empreintes, `&chain=global` ou `group:<id>`). Réservés à super admin, conformité et finance ; les numéros restent masqués pour la finance. Chaque export est journalisé (`staff.data_exported` : qui, quoi, combien de lignes). Format Excel : séparateur « ; », UTF-8 avec BOM, cellules commençant par `= + - @` neutralisées.

Un export sort des données personnelles de l'outil : ne l'envoyez qu'à qui en a besoin, et vérifiez les règles congolaises de protection des données avant tout partage avec un partenaire ou un régulateur.

Risque à garder en tête : valider un « PIN oublié » à la place d'un garant, c'est donner le compte à celui qui tient le numéro. Un voleur de carte SIM peut aussi appeler le support. Vérifiez par des questions que seul le vrai membre connaît (sa tontine, son tour, le président), jamais par le seul numéro.

## Mise en route (développement)

1. API lancée (voir le README racine).
2. Premier compte, depuis `apps/api` :
   ```bash
   npm.cmd run build
   ```
   ```bash
   npm.cmd run admin:create-staff -- --email vous@exemple.cd --name "Votre nom"
   ```
   La commande affiche **une seule fois** le mot de passe provisoire et le secret 2FA : enregistrez le secret dans Google Authenticator, Microsoft Authenticator ou une application équivalente.
3. Back-office, depuis `apps/backoffice` :
   ```bash
   npm.cmd run dev
   ```
   puis ouvrez http://localhost:3001

Variable du back-office : `MCHANGO_API_URL`, l'adresse de l'API vue par le serveur Next.js (défaut : `http://localhost:3000`).

**Pendant que `npm run dev` tourne, ne lancez pas `npm run build`** : les deux écrivent dans `.next`, et le serveur de développement se met à renvoyer des erreurs (scripts introuvables, actions refusées). Pour vérifier que tout compile, utilisez `npm run build:check` : il écrit dans `.next-check`. Si des erreurs étranges apparaissent quand même, arrêtez `npm run dev`, supprimez le dossier `.next` et relancez.

## Pas encore fait (V2 dans le document de cadrage)

Tickets de support complets et réponses types ; formats d'export imposés par un partenaire ou le régulateur ; gel préventif automatique ; facturation ; SMS ciblés ; espace partenaires. La vérification d'identité du recours « PIN oublié » reste manuelle (appel et questions), sans pièce d'identité numérisée.
