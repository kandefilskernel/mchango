import { z } from 'zod';

export const APP_CONFIG = Symbol('APP_CONFIG');

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().min(1),
  REDIS_URL: z.string().min(1),
  JWT_SECRET: z.string().min(32, 'au moins 32 caractères'),
  OTP_PEPPER: z.string().min(32, 'au moins 32 caractères'),
  SMS_DRIVER: z.enum(['console']).default('console'),
  // Les opérateurs mobiles en RDC partagent souvent une même IP publique entre
  // beaucoup d'abonnés (CGNAT) : une limite par IP trop basse bloquerait des
  // utilisateurs légitimes. La vraie protection est la limite par numéro.
  OTP_MAX_PER_IP_PER_HOUR: z.coerce.number().int().positive().default(200),
  TRUST_PROXY: z.enum(['0', '1']).default('0'),
  // Origines autorisées pour un client web (séparées par des virgules). Vide = CORS désactivé.
  // L'app Android n'en a pas besoin ; sert à lancer l'app Flutter dans Chrome en développement.
  CORS_ORIGINS: z.string().default(''),
  // Rappels SMS avant échéance : vérification périodique (voir src/reminders/)
  REMINDERS_ENABLED: z.enum(['0', '1']).default('1'),
  REMINDERS_INTERVAL_MINUTES: z.coerce.number().int().min(1).max(120).default(15),
  // Back-office : secret des jetons de l'équipe (distinct de celui des membres) et clé AES-256
  // (32 octets en base64) qui chiffre les secrets de double authentification en base.
  STAFF_JWT_SECRET: z.string().min(32, 'au moins 32 caractères'),
  STAFF_SECRET_KEY: z
    .string()
    .refine((v) => Buffer.from(v, 'base64').length === 32, '32 octets encodés en base64'),
  // DÉVELOPPEMENT SEULEMENT : le code 2FA « 000000 » est accepté au back-office (tests en local sans
  // application d'authentification). Refusé en production.
  STAFF_2FA_DEV_BYPASS: z.enum(['0', '1']).default('0'),
  // Durée d'une session du back-office : une journée de travail (8 h) ; 24 h au plus en développement
  STAFF_SESSION_HOURS: z.coerce.number().int().min(1).max(24).default(8),
});

export type AppConfig = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((i) => `${i.path.join('.')} : ${i.message}`)
      .join(' ; ');
    throw new Error(`Configuration invalide — ${details}`);
  }
  if (parsed.data.NODE_ENV === 'production' && parsed.data.STAFF_SESSION_HOURS > 12) {
    throw new Error('STAFF_SESSION_HOURS : 12 h au plus en production (une session volée resterait valable trop longtemps)');
  }
  if (parsed.data.NODE_ENV === 'production' && parsed.data.SMS_DRIVER === 'console') {
    throw new Error('SMS_DRIVER=console est interdit en production (les codes seraient dans les logs)');
  }
  if (parsed.data.NODE_ENV === 'production' && parsed.data.STAFF_2FA_DEV_BYPASS === '1') {
    throw new Error('STAFF_2FA_DEV_BYPASS=1 est interdit en production : la double authentification est obligatoire');
  }
  return parsed.data;
}
