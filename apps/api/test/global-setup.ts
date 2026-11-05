// Avant les tests de bout en bout : une base PostgreSQL et une base Redis À PART, recréées à neuf.
// Les tests ne touchent jamais la base de développement (celle qu'on utilise à la main).
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Redis } from 'ioredis';
import pg from 'pg';

export const TEST_DB = 'mchango_test';
/** Redis : base n°1 pour les tests (la n°0 reste au développement). */
export const TEST_REDIS_URL = 'redis://127.0.0.1:6379/1';

// Superutilisateur de la base de développement (docker-compose.yml) : sert seulement à recréer la base de test
const ADMIN_URL = process.env.TEST_ADMIN_DATABASE_URL ?? 'postgres://postgres:postgres_dev@127.0.0.1:5432/postgres';

export default async function setup() {
  const admin = new pg.Client({ connectionString: ADMIN_URL });
  await admin.connect();
  await admin.query(`DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)`);
  await admin.query(`CREATE DATABASE ${TEST_DB}`);
  await admin.end();

  const testDb = new pg.Client({ connectionString: ADMIN_URL.replace(/\/[^/]*$/, `/${TEST_DB}`) });
  await testDb.connect();
  const dir = join(import.meta.dirname, '..', '..', '..', 'db');
  for (const file of readdirSync(dir).filter((f) => /^\d{3}_.*\.sql$/.test(f)).sort()) {
    await testDb.query(readFileSync(join(dir, file), 'utf8'));
  }
  await testDb.end();

  const redis = new Redis(TEST_REDIS_URL);
  await redis.flushdb();
  await redis.quit();
}
