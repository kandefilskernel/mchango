# Mise en ligne : premier test en production (pilote fermé)

Ce guide met Mchango en ligne sur **un seul petit serveur, pour environ 5 € par mois**. Il couvre l'API, la base PostgreSQL, Redis, le back-office et le HTTPS automatique. Durée : environ 30 minutes, dont 10 minutes de compilation.

> **Pilote fermé seulement.** Sans fournisseur SMS, les codes de connexion ne partent pas par SMS : ils s'affichent dans les journaux du serveur, et vous les transmettez vous-même aux testeurs. N'ouvrez pas l'app au public dans ce mode.

## Ce qu'il faut

| Élément | Choix proposé | Coût indicatif (à vérifier au moment d'acheter) |
|---|---|---|
| Serveur | Hetzner Cloud, plus petit serveur (CX22/CX23), Ubuntu 24.04 | environ 4,50 € par mois |
| Adresse + HTTPS | `api.<ip>.sslip.io` et `admin.<ip>.sslip.io` + Let's Encrypt | gratuit |
| Distribution de l'APK | lien de la release GitHub `apk-test`, ou Firebase App Distribution | gratuit |
| Sauvegardes | `backup.sh` chaque nuit (+ Backblaze B2 en option) | gratuit |
| Surveillance | UptimeRobot (offre gratuite) | gratuit |

## 1. Créer le serveur
1. Créez un compte sur hetzner.com, puis un projet.
2. **Sur votre PC**, créez une clé SSH si vous n'en avez pas. Dans PowerShell :
   ```
   ssh-keygen -t ed25519
   ```
   La clé publique est dans `C:\Users\<vous>\.ssh\id_ed25519.pub`.
3. **Add Server** :
   - image **Ubuntu 24.04** ;
   - le plus petit type (CX22 ou CX23) ;
   - une région en Europe (Falkenstein, Nuremberg ou Helsinki) ;
   - collez votre **clé SSH publique** ;
   - pas de mot de passe root.
4. **Firewall** (onglet Firewalls) : n'ouvrez en entrée que **22** (SSH), **80** et **443**.
5. Notez l'**adresse IPv4** du serveur, par exemple `5.75.1.2`.

## 2. Installer Mchango sur le serveur
Depuis PowerShell, connectez-vous :
```
ssh root@5.75.1.2
```
Puis, sur le serveur :
```bash
apt update && apt -y upgrade && apt -y install git unattended-upgrades
curl -fsSL https://get.docker.com | sh
git clone https://github.com/kandefilskernel/mchango.git && cd mchango
git checkout backoffice        # tant que la pull request n'est pas fusionnée dans main
cd infra/prod
sh gen-secrets.sh              # crée .env : secrets neufs et adresses sslip.io
docker compose up -d --build   # environ 10 minutes la première fois
```
`gen-secrets.sh` affiche les adresses de l'API et du back-office. **Copiez le contenu de `.env` dans votre gestionnaire de mots de passe** (`cat .env`). Sans lui, la base ne peut pas être relue après une réinstallation.

Vérifiez dans votre navigateur : `https://api.5-75-1-2.sslip.io/health` doit afficher `{"status":"ok"}`.

## 3. Votre compte administrateur
```bash
docker compose exec api node dist/cli/create-staff.js --email vous@exemple.com --name "Votre nom" --out /tmp/admin.txt
docker compose exec api cat /tmp/admin.txt
docker compose exec api rm /tmp/admin.txt
```
- Ajoutez le secret dans **Google Authenticator**.
- Connectez-vous sur `https://admin.5-75-1-2.sslip.io`, puis changez le mot de passe provisoire.
- En production, **le code 000000 ne marche pas** : la double authentification est obligatoire.

## 4. L'app des testeurs, branchée sur le serveur
1. Sur GitHub, ouvrez le dépôt, puis **Settings → Secrets and variables → Actions → Variables**, et créez la variable `MCHANGO_API_URL` = `https://api.5-75-1-2.sslip.io`.
2. Allez dans **Actions → APK Android → Run workflow**, sur la branche `backoffice`.
3. Environ 10 minutes plus tard, l'APK est disponible sur le même lien qu'avant : `https://github.com/kandefilskernel/mchango/releases/download/apk-test/mchango-test.apk`.
4. Envoyez ce lien aux testeurs. Ils doivent autoriser l'installation d'applications inconnues.

*Option :* **Firebase App Distribution** (gratuit). Créez un projet Firebase, ajoutez une app Android `cd.mchango.mchango`, téléversez l'APK et invitez les testeurs par e-mail. Ils reçoivent les mises à jour.

## 5. Donner les codes de connexion aux testeurs (pilote)
Quand un testeur demande un code dans l'app :
```bash
docker compose logs --since 10m api | grep SMS
```
Repérez la ligne de son numéro et **dites-lui le code de vive voix ou par appel**, jamais en public. Le code expire en 5 minutes.

## 6. Sauvegardes chaque nuit
```bash
crontab -e
```
Ajoutez la ligne :
```
30 2 * * * sh /root/mchango/infra/prod/backup.sh >> /var/log/mchango-backup.log 2>&1
```
Les 14 dernières sauvegardes sont gardées dans `infra/prod/backups/`. **Une sauvegarde qui reste sur le même serveur ne protège pas d'une panne du serveur.** Copiez-les ailleurs : configurez `rclone` avec une destination nommée `sauvegarde:` (par exemple Backblaze B2, 10 Go gratuits) et `backup.sh` l'utilisera tout seul.

Pour restaurer :
```bash
gunzip -c backups/<fichier>.sql.gz | docker compose exec -T postgres psql -U postgres mchango
```
Restaurez dans une base vide.

## 7. Surveillance
Sur uptimerobot.com (gratuit), créez une sonde HTTP sur `https://api.5-75-1-2.sslip.io/health`. Vous serez prévenu par e-mail si l'API ne répond plus.

## 8. Mettre à jour
```bash
cd /root/mchango && git pull && cd infra/prod && docker compose up -d --build
```
Les nouvelles migrations de `db/` s'appliquent toutes seules (service `migrate`). Celles déjà appliquées sont notées dans `schema_migrations`.

## Avant d'ouvrir au public
- [ ] Fournisseur SMS branché, et `SMS_CONSOLE_PILOT=0` dans `.env`.
- [ ] Vrai nom de domaine (`.com` ou `.cd`) à la place de sslip.io.
- [ ] CGU et politique de confidentialité, relues par un juriste.
- [ ] Sauvegardes copiées hors du serveur, et une restauration testée.
- [ ] APK de production signé, et compte Google Play (25 $ une fois).
- [ ] Traductions swahili et lingala relues par des locuteurs.

## Ce qui tourne sur le serveur

| Service | Rôle | Ouvert sur Internet |
|---|---|---|
| `caddy` | HTTPS automatique, renvoie vers l'API et le back-office | oui (80, 443) |
| `api` | API NestJS | non (derrière Caddy) |
| `backoffice` | Back-office Next.js | non (derrière Caddy) |
| `postgres` | Base de données (volume `pgdata`) | non |
| `redis` | Codes, limites, sessions (volume `redisdata`) | non |
| `migrate` | Applique les migrations au démarrage, puis s'arrête | non |
