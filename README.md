# Mchango

Tontine digitale (likelemba / muziki) pour la RDC. Chaque cotisation est déclarée par le payeur, confirmée par le receveur et inscrite dans un journal infalsifiable. **Mchango ne détient, ne transfère et ne garantit jamais d'argent.**

## Organisation du dépôt

| Dossier | Contenu | Outils |
|---------|---------|--------|
| `apps/mobile` | App Android des membres | Flutter 3.47 |
| `apps/api` | Backend, monolithe modulaire REST | NestJS 12, Node 22 |
| `apps/backoffice` | Back-office web de l'équipe (pas développé à l'itération 1) | Next.js 16 |
| `packages/mchango_audit` | Vérification du journal chaîné côté téléphone | Dart pur |
| `db` | Schéma PostgreSQL 16 et tests | Docker |
| `spec` | Format du hash du journal et vecteurs de test communs | |
| `docs` | Cadrage, architecture, revue du schéma | |

## Vérifier que tout fonctionne

```bash
cd packages/mchango_audit && dart test
```

```bash
cd apps/mobile && flutter test
```

```bash
cd apps/api && npm install && npm test
```

```bash
cd apps/backoffice && npm install && npm run build
```

Tests de la base : voir [`db/README.md`](db/README.md).

> `npm install` dans `apps/api` peut échouer avec npm 10 (`Cannot read properties of null (reading 'edgesOut')`, bug du résolveur). Dans ce cas : `npx npm@11 install`.

## Documentation

- [Document de cadrage](Tontine%20digitale%20RDC%20-%20Document%20de%20cadrage.docx)
- [Architecture et arbitrages](docs/architecture.md)
- [Revue du schéma de base de données](docs/revue-schema.md)
- [Format du hash du journal](spec/audit-hash.md)
