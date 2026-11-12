# Mchango — app mobile (Flutter)

App Android des membres. Français uniquement à l'itération 1.

## Parcours

| Écran | Fichier |
|-------|---------|
| Numéro → code SMS → nom + PIN (ou PIN d'un compte existant) | `lib/ui/auth/sign_in_flow.dart` |
| Ouverture par PIN | `lib/ui/auth/unlock_screen.dart` |
| Mes tontines, créer, rejoindre (aperçu du règlement avant d'accepter) | `lib/ui/groups/` |
| Préparation : inviter, ordre des tours (glisser ou tirage), démarrer | `lib/ui/groups/group_screen.dart`, `turn_order_screen.dart` |
| Tableau des tours, « J'ai payé », « J'ai reçu », témoin, contestation | `lib/ui/cycles/` |
| Reçu avec QR code, partage en image | `lib/ui/receipts/receipt_screen.dart` |
| Historique vérifié sur le téléphone | `lib/ui/history/history_screen.dart` |

## Sécurité sur le téléphone

- **Clé de l'appareil** : Ed25519 générée sur le téléphone. La graine privée reste dans le stockage sécurisé (Keystore Android) ; seule la clé publique part au serveur. Chaque session s'ouvre en signant un défi.
- **PIN** : jamais stocké. Seule une empreinte PBKDF2-HMAC-SHA256 (60 000 itérations, sel aléatoire) est gardée pour déverrouiller sans réseau. Après 5 PIN faux, pause de 5 minutes.
- **Verrouillage** : l'app redemande le PIN après 2 minutes en arrière-plan.
- **Historique** : l'app recalcule la chaîne de hash du journal avec `packages/mchango_audit` et garde le dernier point vérifié. Si le serveur présente plus tard un autre contenu pour un événement déjà vérifié, elle alerte.
- **Déclarations** : chaque déclaration porte un identifiant créé sur le téléphone ; la renvoyer après une coupure réseau ne crée pas de doublon.

## Lancer

L'API doit tourner (voir le README racine). Adresse de l'API : `--dart-define=API_URL=...`. Par défaut, c'est la machine de développement : `http://10.0.2.2:3000` depuis l'émulateur Android, `http://localhost:3000` depuis Chrome.

```bash
flutter run
```

Dans Chrome (l'API doit autoriser l'origine : `CORS_ORIGINS=http://localhost:8080` dans `apps/api/.env`) :

```bash
flutter run -d chrome --web-port 8080
```

## Tests

```bash
flutter test
```

Test d'intégration contre la vraie API : rotation complète à 3 avec le code de l'app. Lancer d'abord l'API avec ses logs dans un fichier (les codes SMS y apparaissent) :

```bash
cd ../api && npm run build && NO_COLOR=1 node dist/main.js > /tmp/mchango-api.log 2>&1
```

Puis, dans un autre terminal :

```bash
MCHANGO_API_URL=http://localhost:3000 MCHANGO_API_LOG=/tmp/mchango-api.log flutter test test/integration/real_api_test.dart
```

## Limites connues

- **Android 7.0 (API 24) minimum**, imposé par Flutter et le stockage sécurisé. Les téléphones plus anciens ne sont pas pris en charge.
- **Hors ligne** : l'app a besoin du réseau pour afficher et déclarer. Le mode hors ligne complet (file d'attente locale) est reporté, comme prévu dans le cadrage.
- **Textes** : en français, directement dans le code. Swahili et lingala demanderont de passer aux fichiers de traduction (ARB).
- **Vérification d'un reçu par scan du QR** : V2. Le QR contient déjà le numéro, la cotisation, le groupe, et l'événement du journal (`seq` + `hash`).
- **APK** : pas encore compilé ni testé sur un vrai téléphone Android (le SDK Android n'est pas installé sur la machine de développement actuelle).
