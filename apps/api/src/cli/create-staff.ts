// Crée un compte d'équipe depuis la ligne de commande (indispensable pour le premier super admin) :
//   npm.cmd run admin:create-staff -- --email ana@mchango.cd --name "Ana Kabwe" [--role super_admin]
// Affiche UNE SEULE FOIS le mot de passe provisoire et le secret de double authentification.
import { NestFactory } from '@nestjs/core';
import { parseArgs } from 'node:util';
import { StaffAuthService, STAFF_ROLES, type StaffRole } from '../admin/staff-auth.service.js';
import { AppModule } from '../app.module.js';

async function main() {
  try {
    process.loadEnvFile('.env');
  } catch {
    // variables déjà dans l'environnement
  }
  process.env.REMINDERS_ENABLED = '0'; // pas de rappels depuis un outil en ligne de commande

  const { values } = parseArgs({
    options: {
      email: { type: 'string' },
      name: { type: 'string' },
      role: { type: 'string', default: 'super_admin' },
    },
  });
  if (!values.email || !values.name || !STAFF_ROLES.includes(values.role as StaffRole)) {
    console.error(`Usage : --email <e-mail> --name "<nom>" [--role ${STAFF_ROLES.join('|')}]`);
    process.exit(1);
  }

  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error'] });
  try {
    const created = await app.get(StaffAuthService).create(null, {
      email: values.email,
      fullName: values.name,
      role: values.role as StaffRole,
    });
    console.log(`
Compte créé : ${created.email} (${values.role})

  Mot de passe provisoire : ${created.temporaryPassword}
  Secret double authentification : ${created.totpSecret}

1. Dans une application d'authentification (Google Authenticator, Microsoft Authenticator…),
   ajoutez un compte avec ce secret (« saisir une clé de configuration »), type « basé sur l'heure ».
   Ou transformez ce lien en QR code :
   ${created.otpauthUrl}
2. Connectez-vous au back-office avec l'e-mail, ce mot de passe et le code à 6 chiffres.
3. Changez le mot de passe provisoire dès la première connexion.

Ces informations ne seront plus jamais affichées : notez-les maintenant, en lieu sûr.
`);
  } finally {
    await app.close();
  }
}

await main();
