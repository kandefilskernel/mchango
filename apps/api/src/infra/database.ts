import {
  Global,
  Inject,
  Injectable,
  Module,
  OnModuleDestroy,
} from '@nestjs/common';
import pg from 'pg';
import { APP_CONFIG, type AppConfig } from '../config.js';

export const PG_POOL = Symbol('PG_POOL');

/** Auteur d'une écriture, transmis aux triggers de journalisation (voir db/README.md). */
export interface Actor {
  type: 'user' | 'staff' | 'system';
  id?: string;
  deviceId?: string;
}

export type Queryable = Pick<pg.PoolClient, 'query'>;

@Injectable()
export class Db implements OnModuleDestroy {
  constructor(@Inject(PG_POOL) private readonly pool: pg.Pool) {}

  query<R extends pg.QueryResultRow>(text: string, params?: unknown[]) {
    return this.pool.query<R>(text, params);
  }

  /** Transaction dont toutes les écritures sont attribuées à [actor] dans le journal. */
  async transaction<T>(actor: Actor, fn: (q: Queryable) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query(
        `SELECT set_config('mchango.actor_type', $1, true),
                set_config('mchango.actor_id', $2, true),
                set_config('mchango.device_id', $3, true)`,
        [actor.type, actor.id ?? '', actor.deviceId ?? ''],
      );
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}

/** Code d'erreur PostgreSQL pour une violation d'unicité. */
export const UNIQUE_VIOLATION = '23505';

export function isUniqueViolation(error: unknown, constraint?: string): boolean {
  const e = error as { code?: string; constraint?: string };
  return e?.code === UNIQUE_VIOLATION && (!constraint || e.constraint === constraint);
}

/**
 * Ajoute un événement au journal (chaîne du groupe, ou chaîne « global » si [groupId] est null).
 * Pour les événements qui ne passent pas par une table métier journalisée (authentification…).
 */
export async function appendAudit(
  q: Queryable,
  event: { groupId: string | null; actor: Actor; action: string; payload: object },
): Promise<void> {
  await q.query(
    `INSERT INTO audit_log (group_id, actor_type, actor_id, device_id, action, payload)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [
      event.groupId,
      event.actor.type,
      event.actor.id ?? null,
      event.actor.deviceId ?? null,
      event.action,
      JSON.stringify(event.payload),
    ],
  );
}

@Global()
@Module({
  providers: [
    {
      provide: PG_POOL,
      inject: [APP_CONFIG],
      useFactory: (config: AppConfig) =>
        new pg.Pool({ connectionString: config.DATABASE_URL, max: 10 }),
    },
    Db,
  ],
  exports: [Db],
})
export class DatabaseModule {}
