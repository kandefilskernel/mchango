import type { Queryable } from '../infra/database.js';

export interface ActiveMembership {
  id: string;
  role: 'member' | 'treasurer' | 'president';
}

/** Adhésion active de l'utilisateur dans le groupe, ou null. */
export async function activeMembership(
  q: Queryable,
  userId: string,
  groupId: string,
): Promise<ActiveMembership | null> {
  const { rows } = await q.query<ActiveMembership>(
    `SELECT id, role FROM memberships WHERE group_id = $1 AND user_id = $2 AND status = 'active'`,
    [groupId, userId],
  );
  return rows[0] ?? null;
}

/** Date du jour à Lubumbashi (UTC+2), calculée par PostgreSQL. */
export const TODAY_DRC_SQL = `(now() AT TIME ZONE 'Africa/Lubumbashi')::date`;
