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

| Rôle | Lire | Voir les numéros | Bloquer, révoquer un téléphone | Suspendre une tontine | Trancher un litige | Gérer l'équipe |
|------|:----:|:----------------:|:------------------------------:|:---------------------:|:------------------:|:--------------:|
| Super admin | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Conformité | ✓ | ✓ | ✓ | ✓ | ✓ | |
| Support | ✓ | ✓ | ✓ | | | |
| Finance | ✓ | masqués (`+243 99 *** **67`) | | | | |
| Lecture seule | ✓ | masqués | | | | |

Les droits sont contrôlés **par l'API**. L'interface ne fait que masquer les boutons inutiles.

## Ce que l'équipe peut faire, et ce qu'elle ne peut pas faire

- Toute action est inscrite dans le **journal**, avec l'acteur « staff ». Celles qui concernent une tontine (suspension, décision de litige) vont dans **la chaîne de cette tontine** et sont donc **visibles des membres** dans leur historique.
- **Litige, rejet** : la déclaration passe `rejected` et le litige `resolved_rejected` ; le payeur peut déclarer de nouveau, avec un vrai ID de transaction.
- **Litige, avis** : la note est ajoutée, le litige reste ouvert ; les parties s'accordent.
- L'équipe **ne peut jamais confirmer un paiement** à la place du bénéficiaire : elle ne voit pas l'argent. Elle ne peut pas rejeter un paiement déjà confirmé par le bénéficiaire.
- **Suspension** : plus de déclarations ni de rappels ; la réactivation rend le statut d'avant (préparation ou en cours).

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

## Pas encore fait (V2 dans le document de cadrage)

Tickets de support et réponses types ; exports pour partenaires et régulateur ; règles d'alerte de fraude et gel préventif ; facturation ; SMS ciblés ; espace partenaires. Pas encore de recours « PIN oublié » traité par le support.
