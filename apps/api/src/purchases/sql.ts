import type { Actor, Queryable } from '../infra/database.js';

export const SYSTEM: Actor = { type: 'system' };

/** Lignes d'une requête (Db ou client de transaction). */
export async function rows<T = Record<string, any>>(
  q: Queryable,
  text: string,
  params?: unknown[],
): Promise<T[]> {
  const result = await q.query(text, params);
  return result.rows as T[];
}

// pg renvoie les BIGINT (montants, sommes) en texte : on les remet en nombre pour l'API.
const NUMERIC_KEY = /(Minor|Units|Members|^quantity)$/;
const camel = (key: string) => key.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());

/** Ligne SQL → JSON de l'API : clés en camelCase, montants en nombres. */
export function toApi<T = any>(value: unknown): T {
  if (Array.isArray(value)) return value.map((v) => toApi(v)) as T;
  if (value === null || typeof value !== 'object' || value instanceof Date) return value as T;
  return Object.fromEntries(
    Object.entries(value).map(([key, v]) => {
      const k = camel(key);
      const converted =
        NUMERIC_KEY.test(k) && typeof v === 'string' && /^-?\d+$/.test(v) ? Number(v) : toApi(v);
      return [k, converted];
    }),
  ) as T;
}
