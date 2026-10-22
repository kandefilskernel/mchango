# Mchango — back-office

Administration réservée à l'équipe (Next.js) : tableau de bord, utilisateurs, tontines, litiges, audit, équipe.

Fonctionnement, rôles et sécurité : [`spec/backoffice.md`](../../spec/backoffice.md).

## Lancer en développement

L'API doit tourner (port 3000). Puis :

```bash
npm.cmd install
```

```bash
npm.cmd run dev
```

Le back-office s'ouvre sur http://localhost:3001. Le premier compte se crée avec `npm.cmd run admin:create-staff` dans `apps/api` (voir la spec).

## Principes

- Le navigateur ne parle **jamais** directement à l'API : le serveur Next.js l'appelle avec le jeton gardé dans un cookie `httpOnly` (`src/lib/api.ts`).
- Chaque formulaire est une action serveur (`src/app/actions.ts`). L'API revérifie le rôle et journalise chaque action.
- Pas de mode « Cache Components » : chaque page dépend de la personne connectée.
