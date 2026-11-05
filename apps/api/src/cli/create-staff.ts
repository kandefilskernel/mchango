// Comptes d'équipe depuis la ligne de commande (indispensable pour le premier super admin) :
//   npm.cmd run admin:create-staff -- --email ana@mchango.cd --name "Ana Kabwe" [--role super_admin]
// Nouveaux identifiants pour un compte existant (téléphone perdu, identifiants jamais notés) :
//   npm.cmd run admin:create-staff -- --email ana@mchango.cd --reset
// --out <fichier> : écrit les identifiants dans ce fichier au lieu de l'écran.
// Les identifiants ne sont donnés qu'UNE SEULE FOIS.
import { NestFactory } from '@nestjs/core';
import { writeFileSync } from 'node:fs';
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
      reset: { type: 'boolean', default: false },
      out: { type: 'string' },
    },
  });
  const valid = values.reset ? !!values.email : !!values.email && !!values.name && STAFF_ROLES.includes(values.role as StaffRole);
  if (!valid) {
    console.error(
      `Usage : --email <e-mail> --name "<nom>" [--role ${STAFF_ROLES.join('|')}] [--out <fichier>]\n` +
        `        --email <e-mail> --reset [--out <fichier>]`,
    );
    process.exit(1);
  }

  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error'] });
  try {
    const staff = app.get(StaffAuthService);
    const r = values.reset
      ? await staff.resetCredentials(values.email!)
      : await staff.create(null, { email: values.email!, fullName: values.name!, role: values.role as StaffRole });
    const text = `MCHANGO - BACK-OFFICE - ${values.reset ? 'NOUVEAUX IDENTIFIANTS' : 'COMPTE CRÉÉ'}

E-mail : ${r.email}
Mot de passe provisoire : ${r.temporaryPassword}
Secret double authentification : ${r.totpSecret}

1. Sur votre téléphone, dans Google Authenticator (ou Microsoft Authenticator) :
   « + » puis « Saisir une clé de configuration ».
   Nom du compte : Mchango. Clé : le secret ci-dessus. Type : basé sur l'heure.
   (Ou transformez ce lien en QR code : ${r.otpauthUrl} )
2. Back-office (http://localhost:3001 en développement) : e-mail, mot de passe provisoire,
   et le code à 6 chiffres affiché par l'application.
3. Changez le mot de passe provisoire dès la première connexion.
${values.reset ? '\nLes anciens identifiants de ce compte ne fonctionnent plus.\n' : ''}
SUPPRIMEZ CE FICHIER une fois le secret enregistré et le mot de passe changé.
`;
    if (values.out) {
      writeFileSync(values.out, text, { encoding: 'utf8', mode: 0o600 });
      console.log(`Identifiants écrits dans ${values.out}. Ouvrez ce fichier, puis supprimez-le après usage.`);
    } else {
      console.log(`\n${text}`);
    }
  } finally {
    await app.close();
  }
}

await main();
